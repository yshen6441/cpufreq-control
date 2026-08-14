#import "ViewController.h"
#import "NodeMobile.h"

static NSString *const kServerURLKey = @"DSHServerURL";
static NSString *const kDefaultServerURL = @"http://192.168.95.36:3080";
static NSString *const kLocalModeKey = @"DSHLocalMode";
static NSString *const kAPIKeyKey = @"DSHAPIKey";
static NSString *const kLocalServerURL = @"http://127.0.0.1:3080";

@implementation ViewController {
	BOOL _localStarted;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor systemBackgroundColor];

	// ---- WKWebView ----
	WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
	config.allowsInlineMediaPlayback = YES;
	config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

	self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
	self.webView.navigationDelegate = self;
	self.webView.UIDelegate = self;
	self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.webView];

	// ---- 底部工具条 ----
	self.toolbar = [[UIToolbar alloc] init];
	self.toolbar.translucent = YES;
	[self.view addSubview:self.toolbar];

	UIBarButtonItem *back = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]
															 style:UIBarButtonItemStylePlain
															target:self action:@selector(goBack)];
	UIBarButtonItem *forward = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]
																style:UIBarButtonItemStylePlain
															   target:self action:@selector(goForward)];
	UIBarButtonItem *reload = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
															  style:UIBarButtonItemStylePlain
															 target:self action:@selector(reloadPage)];
	UIBarButtonItem *server = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"server.rack"]
															  style:UIBarButtonItemStylePlain
															 target:self action:@selector(openSettings)];
	UIBarButtonItem *flex1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

	self.toolbar.items = @[ back, flex1, forward, reload, flex2, server ];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	CGFloat barHeight = 44.0 + self.view.safeAreaInsets.bottom;
	self.toolbar.frame = CGRectMake(0, bounds.size.height - barHeight, bounds.size.width, barHeight);
	self.webView.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height - barHeight);
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self ensureServer];
}

#pragma mark - 服务器 (本地 / 远程)

- (BOOL)isLocalMode {
	NSNumber *v = [[NSUserDefaults standardUserDefaults] objectForKey:kLocalModeKey];
	return v == nil ? YES : v.boolValue; // 默认本地模式
}

- (void)ensureServer {
	if (self.isLocalMode) {
		[self startLocalServer];
	} else {
		NSString *url = [[NSUserDefaults standardUserDefaults] stringForKey:kServerURLKey];
		if (url.length == 0) {
			[self promptForServerURL];
		} else if (!self.webView.URL || self.webView.URL.absoluteString.length == 0) {
			[self loadURLString:url];
		}
	}
}

/** 启动内嵌 Node.js 运行 DSH (后台线程), 就绪后加载 localhost */
- (void)startLocalServer {
	if (_localStarted) {
		if (!self.webView.URL || self.webView.URL.absoluteString.length == 0) {
			[self loadURLString:kLocalServerURL];
		}
		return;
	}
	_localStarted = YES;

	// 先保存 API key
	[self saveAPIKeyToFile];

	// 后台线程跑 node (node_start 是阻塞的)
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"server" ofType:@"mjs" inDirectory:@"runtime"];
		if (!scriptPath) {
			NSLog(@"[DSH] runtime/server.mjs 不存在");
			return;
		}
		char *argv[] = { "node", (char *)scriptPath.UTF8String, NULL };
		NSLog(@"[DSH] 启动内嵌 Node: %@", scriptPath);
		node_start(2, argv);
		NSLog(@"[DSH] node 退出");
	});

	// 轮询 localhost:3080 就绪 (最长 20 秒)
	[self waitForLocalServerThenLoad];
}

- (void)waitForLocalServerThenLoad {
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BOOL ready = NO;
		for (int i = 0; i < 40; i++) {
			NSURL *probe = [NSURL URLWithString:@"http://127.0.0.1:3080/"];
			NSURLRequest *req = [NSURLRequest requestWithURL:probe cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:2];
			NSURLResponse *resp = nil;
			NSError *err = nil;
			[NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
			if (resp && !err) { ready = YES; break; }
			[NSThread sleepForTimeInterval:0.5];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;
			if (ready) {
				[self loadURLString:kLocalServerURL];
			} else {
				[self showAlert:@"本地服务器启动超时" message:@"内嵌 Node.js 未能就绪, 请重启 App 重试。"];
			}
		});
	});
}

/** API key 写入 Documents/dsh-key.txt (server.mjs 读取) */
- (void)saveAPIKeyToFile {
	NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:kAPIKeyKey];
	if (key.length == 0) return;
	NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	NSString *path = [docDir stringByAppendingPathComponent:@"dsh-key.txt"];
	[key writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - 设置

- (void)openSettings {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"DSH 设置"
																message:@"运行模式与 API Key"
														 preferredStyle:UIAlertControllerStyleAlert];

	NSString *modeTitle = self.isLocalMode ? @"当前: 本地模式 (内嵌服务器)" : @"当前: 远程模式 (连接电脑服务器)";
	[ac addAction:[UIAlertAction actionWithTitle:modeTitle
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *a) {
		BOOL local = !self.isLocalMode;
		[[NSUserDefaults standardUserDefaults] setBool:local forKey:kLocalModeKey];
		[self.webView stopLoading];
		if (local) {
			[self ensureServer];
		} else {
			[self promptForServerURL];
		}
	}]];

	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:kAPIKeyKey];
		tf.text = key;
		tf.placeholder = @"sk-... (DeepSeek API Key)";
		tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[ac addAction:[UIAlertAction actionWithTitle:@"保存 Key"
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *a) {
		NSString *key = [ac.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[[NSUserDefaults standardUserDefaults] setObject:key forKey:kAPIKeyKey];
		[self saveAPIKeyToFile];
		[self showAlert:@"已保存" message:@"API Key 已保存, 重启 App 后生效。\n获取 Key: platform.deepseek.com"];
	}]];

	[ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (void)promptForServerURL {
	NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:kServerURLKey];

	UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"DSH 服务器地址"
																message:@"输入 DeepSeek Harness 服务器的网址（自动补全 http://）"
														 preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.text = current.length ? current : kDefaultServerURL;
		tf.keyboardType = UIKeyboardTypeURL;
		tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[ac addAction:[UIAlertAction actionWithTitle:@"连接"
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *action) {
		NSString *s = [ac.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (s.length == 0) s = kDefaultServerURL;
		if (![s hasPrefix:@"http://"] && ![s hasPrefix:@"https://"]) s = [@"http://" stringByAppendingString:s];
		[[NSUserDefaults standardUserDefaults] setObject:s forKey:kServerURLKey];
		[self loadURLString:s];
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (void)loadURLString:(NSString *)s {
	NSURL *url = [NSURL URLWithString:s];
	if (!url) return;
	[self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
																message:message
														 preferredStyle:UIAlertControllerStyleAlert];
	[ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 工具条动作

- (void)goBack {
	if (self.webView.canGoBack) [self.webView goBack];
}

- (void)goForward {
	if (self.webView.canGoForward) [self.webView goForward];
}

- (void)reloadPage {
	if (self.webView.URL) {
		[self.webView reload];
	} else {
		[self ensureServer];
	}
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	if (error.code == NSURLErrorCancelled) return;
	[self showAlert:@"无法连接"
			message:[NSString stringWithFormat:@"请检查服务器状态和网络。\n(%@)", error.localizedDescription]];
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
	[webView loadRequest:navigationAction.request];
	return nil;
}

@end
