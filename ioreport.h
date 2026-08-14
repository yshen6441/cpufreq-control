// ioreport.h - 通过 IOReport 私有 API 读取 CPU 实时频率
#ifndef IOREPORT_H
#define IOREPORT_H

#import <Foundation/Foundation.h>

// 初始化 IOReport 订阅 (惰性, 可重复调用)
void IOReportInit(void);

// 返回每个 CPU 簇的当前频率 (MHz)。
// 典型返回: [P核频率, E核频率] (A14 上为 2 个簇)
NSArray<NSNumber *> *IOReportReadFrequencies(void);

#endif
