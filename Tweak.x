// CPUFreqControl - 自定义CPU限频插件
// 原理: 调用 thermalmonitord 中 CommonProduct 的
//       putDeviceInThermalSimulationMode: 私有方法, 通过"热仿真"让系统
//       把CPU最高频率限制到对应档位 (与 Powercuff 同机制, 本插件扩展为
//       多档 + 自定义模式字符串 + 低电量联动 + 设置即时生效)。
//
// 进程注入:
//   - thermalmonitord : 应用热仿真模式 (真正生效处)
//   - SpringBoard     : 监听低电量模式切换, 触发重新应用
//
// 设置变更流程:
//   设置App -> notify_post("com.infrastructure.cpufreq.reload")
//          -> thermalmonitord 收到通知 -> 读偏好文件 -> 应用模式

#import <Foundation/Foundation.h>
#import <notify.h>

extern char ***_NSGetArgv(void);

static const char *kReloadNotification = "com.infrastructure.cpufreq.reload";
static NSString *kPrefsPath = @"/var/mobile/Library/Preferences/com.infrastructure.cpufreq.plist";

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)simulationMode;
@end

@interface _CDBatterySaver : NSObject
+ (_CDBatterySaver *)batterySaver;
- (NSInteger)getPowerMode;
@end

static CommonProduct *currentProduct;

static NSString *StringForThermalMode(uint64_t mode) {
	switch (mode) {
		case 1:  return @"nominal";
		case 2:  return @"light";
		case 3:  return @"moderate";
		case 4:  return @"heavy";
		default: return @"off";
	}
}

static void ApplyThermals(void) {
	if (!currentProduct) {
		return;
	}
	if (![currentProduct respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
		NSLog(@"[CPUFreq] CommonProduct does not respond to putDeviceInThermalSimulationMode: (iOS 17 changed API?)");
		return;
	}

	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
	NSString *modeString = nil;

	if (prefs) {
		id enabledValue = prefs[@"Enabled"];
		BOOL enabled = !enabledValue || [enabledValue respondsToSelector:@selector(boolValue)] == NO || [enabledValue boolValue];

		if (enabled) {
			BOOL requireLPM = [prefs[@"RequireLowPowerMode"] respondsToSelector:@selector(boolValue)] && [prefs[@"RequireLowPowerMode"] boolValue];

			// 低电量模式状态 (_CDBatterySaver 来自 CoreDuet, 通常已在共享缓存中)
			BOOL inLowPowerMode = NO;
			Class batterySaverClass = NSClassFromString(@"_CDBatterySaver");
			if (batterySaverClass && [batterySaverClass respondsToSelector:@selector(batterySaver)]) {
				id batterySaver = [batterySaverClass batterySaver];
				if (batterySaver && [batterySaver respondsToSelector:@selector(getPowerMode)]) {
					inLowPowerMode = ([batterySaver getPowerMode] != 0);
				}
			}

			if (!requireLPM || inLowPowerMode) {
				id customMode = prefs[@"CustomMode"];
				if ([customMode isKindOfClass:[NSString class]] && [(NSString *)customMode length] > 0) {
					modeString = (NSString *)customMode;
				} else {
					NSInteger mode = [prefs[@"Mode"] respondsToSelector:@selector(integerValue)] ? [prefs[@"Mode"] integerValue] : 0;
					modeString = StringForThermalMode((uint64_t)mode);
				}
			}
		}
	}

	if (!modeString) {
		modeString = @"off";
	}

	[currentProduct putDeviceInThermalSimulationMode:modeString];
	NSLog(@"[CPUFreq] applied thermal simulation mode: %@", modeString);
}

%group thermalmonitord

%hook CommonProduct

- (id)initProduct:(id)data
{
	self = %orig();
	if (self) {
		if ([self respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
			currentProduct = self;
			ApplyThermals();
		}
	}
	return self;
}

- (void)dealloc
{
	if (currentProduct == self) {
		currentProduct = nil;
	}
	%orig();
}

%end

%end

%group SpringBoard

%hook SpringBoard

- (void)_batterySaverModeChanged:(NSInteger)token
{
	%orig();
	// 低电量模式切换 -> 重新应用限频设置
	notify_post(kReloadNotification);
}

%end

%end

%ctor
{
	char *argv0 = **_NSGetArgv();
	char *path = strrchr(argv0, '/');
	path = path == NULL ? argv0 : path + 1;

	if (strcmp(path, "thermalmonitord") == 0) {
		// 真正的应用者: 收到通知后重新读取设置并应用
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
			(void *)ApplyThermals, CFSTR("com.infrastructure.cpufreq.reload"), NULL,
			CFNotificationSuspensionBehaviorCoalesce);
		%init(thermalmonitord);
	} else {
		%init(SpringBoard);
	}
}
