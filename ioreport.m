// ioreport.m - IOReport 私有 API 封装 (dlsym 动态加载, 无需链接私有库)
#import "ioreport.h"
#import <dlfcn.h>

typedef struct io_report_sample_s {
	uint64_t io_report_channel;
	uint64_t io_report_group;
	uint64_t io_report_state;
	uint64_t io_report_value;
	uint64_t io_report_count;
	uint64_t io_report_values[];
} io_report_sample_t;

typedef CFTypeRef (*IOReportCreate_t)(CFAllocatorRef, CFAllocatorRef, int);
typedef CFArrayRef (*IOReportCopyChannelsInGroup_t)(CFTypeRef, CFStringRef, CFStringRef, uint64_t, uint64_t, int);
typedef CFTypeRef (*IOReportCreateSubscription_t)(CFAllocatorRef, CFAllocatorRef, CFArrayRef, int, uint64_t, int);
typedef CFArrayRef (*IOReportGetDeltaEvent_t)(CFTypeRef, CFMutableDictionaryRef, CFMutableDictionaryRef);

static IOReportCreate_t p_IOReportCreate;
static IOReportCopyChannelsInGroup_t p_IOReportCopyChannelsInGroup;
static IOReportCreateSubscription_t p_IOReportCreateSubscription;
static IOReportGetDeltaEvent_t p_IOReportGetDeltaEvent;

static CFTypeRef report;
static CFTypeRef subscription;
static BOOL available;

void IOReportInit(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		void *handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY);
		if (!handle) {
			handle = dlopen("libIOReport.dylib", RTLD_LAZY);
		}
		if (!handle) {
			NSLog(@"[CPUFreq] failed to dlopen libIOReport");
			return;
		}
		p_IOReportCreate = (IOReportCreate_t)dlsym(handle, "IOReportCreate");
		p_IOReportCopyChannelsInGroup = (IOReportCopyChannelsInGroup_t)dlsym(handle, "IOReportCopyChannelsInGroup");
		p_IOReportCreateSubscription = (IOReportCreateSubscription_t)dlsym(handle, "IOReportCreateSubscription");
		p_IOReportGetDeltaEvent = (IOReportGetDeltaEvent_t)dlsym(handle, "IOReportGetDeltaEvent");
		if (!p_IOReportCreate || !p_IOReportCopyChannelsInGroup || !p_IOReportCreateSubscription || !p_IOReportGetDeltaEvent) {
			NSLog(@"[CPUFreq] IOReport symbols not found");
			return;
		}
		report = p_IOReportCreate(NULL, NULL, 0);
		if (!report) {
			NSLog(@"[CPUFreq] IOReportCreate failed");
			return;
		}
		CFArrayRef channels = p_IOReportCopyChannelsInGroup(report, CFSTR("CPU Stats"), CFSTR("CPU Frequency"), 0, 0, 0);
		if (!channels || CFArrayGetCount(channels) == 0) {
			// 回退: 取整个组的所有通道
			if (channels) CFRelease(channels);
			channels = p_IOReportCopyChannelsInGroup(report, CFSTR("CPU Stats"), CFSTR(""), 0, 0, 0);
		}
		if (!channels || CFArrayGetCount(channels) == 0) {
			NSLog(@"[CPUFreq] no CPU Frequency channels found");
			if (channels) CFRelease(channels);
			return;
		}
		subscription = p_IOReportCreateSubscription(NULL, NULL, channels, 0, 0, 0);
		CFRelease(channels);
		if (!subscription) {
			NSLog(@"[CPUFreq] IOReportCreateSubscription failed");
			return;
		}
		// 预热: 丢弃基线增量
		CFArrayRef baseline = p_IOReportGetDeltaEvent(subscription, NULL, NULL);
		if (baseline) CFRelease(baseline);
		available = YES;
		NSLog(@"[CPUFreq] IOReport CPU Frequency subscription ready");
	});
}

NSArray<NSNumber *> *IOReportReadFrequencies(void) {
	IOReportInit();
	if (!available || !subscription) {
		return @[];
	}
	CFArrayRef samples = p_IOReportGetDeltaEvent(subscription, NULL, NULL);
	if (!samples) {
		return @[];
	}
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	CFIndex count = CFArrayGetCount(samples);
	for (CFIndex i = 0; i < count; i++) {
		CFDataRef data = CFArrayGetValueAtIndex(samples, i);
		if (CFGetTypeID(data) != CFDataGetTypeID()) {
			continue;
		}
		io_report_sample_t *sample = (io_report_sample_t *)CFDataGetBytePtr(data);
		if (!sample) {
			continue;
		}
		// CPU Frequency 通道: values[0] = 频率 (Hz)
		if (sample->io_report_count >= 1) {
			double mhz = (double)sample->io_report_values[0] / 1000000.0;
			[result addObject:@(mhz)];
		}
	}
	CFRelease(samples);
	return result;
}
