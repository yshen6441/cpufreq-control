// CPUFreqPrefs.m - 设置面板: 限频档位配置 + 实时频率显示
#import <Preferences/Preferences.h>
#import <notify.h>
#import "ioreport.h"

@interface CPUFreqPrefsListController : PSListController
@end

@implementation CPUFreqPrefsListController {
	NSTimer *_refreshTimer;
}

- (id)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	// 初始化 IOReport 并丢弃基线
	IOReportInit();
	IOReportReadFrequencies();

	_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
													 target:self
												   selector:@selector(refreshFrequency)
												   userInfo:nil
													repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_refreshTimer invalidate];
	_refreshTimer = nil;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];

	// 除实时频率显示单元外, 任何设置变更都通知插件立即重新应用
	NSString *key = [specifier propertyForKey:@"key"];
	if (![key isEqualToString:@"LiveFreq"]) {
		notify_post("com.infrastructure.cpufreq.reload");
	}
}

- (void)applyNow {
	notify_post("com.infrastructure.cpufreq.reload");

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已应用"
																   message:@"限频设置已发送, 请留意发热/性能变化。\n可在\"实时频率\"处观察当前频率。"
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshFrequency {
	NSArray<NSNumber *> *freqs = IOReportReadFrequencies();
	NSString *text;
	if (freqs.count >= 2) {
		text = [NSString stringWithFormat:@"P核: %.0f MHz     E核: %.0f MHz",
				freqs[0].doubleValue, freqs[1].doubleValue];
	} else if (freqs.count == 1) {
		text = [NSString stringWithFormat:@"CPU: %.0f MHz", freqs[0].doubleValue];
	} else {
		text = @"无数据 (IOReport 不可用)";
	}

	for (PSSpecifier *spec in _specifiers) {
		if ([[spec propertyForKey:@"key"] isEqualToString:@"LiveFreq"]) {
			[self setPreferenceValue:text specifier:spec];
			[self reloadSpecifier:spec];
			break;
		}
	}
}

@end
