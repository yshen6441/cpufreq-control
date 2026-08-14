#import "ViewController.h"

static NSString *const kServerURLKey = @"DSHServerURL";
static NSString *const kDefaultServerURL = @"http://192.168.95.36:3080";

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor systemBackgroundColor];

	// ---- WKWebView ----
	WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
	config.allowsInlineMediaPlayback = YES;
	config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
	config.suppressesIncrementalRendering = NO;

	self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
	self.webView.navigationDelegate = self;
	self.webView.UIDelegate = self;
	self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.webView];

	// ---- 底部工具条: 后退 / 前进 / 刷新 / 服务器 ----
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
															 target:self action:@selector(changeServer)];
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

#pragma mark - 服务器地址

- (void)ensureServer {
	NSString *url = [[NSUserDefaults standardUserDefaults] stringForKey:kServerURLKey];
	if (url.length == 0) {
		[self promptForServerURL];
	} else if (!self.webView.URL || self.webView.URL.absoluteString.length == 0) {
		[self loadURLString:url];
	}
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
		tf.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	[ac addAction:[UIAlertAction actionWithTitle:@"连接"
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *action) {
		NSString *s = [ac.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (s.length == 0) {
			s = kDefaultServerURL;
		}
		if (![s hasPrefix:@"http://"] && ![s hasPrefix:@"https://"]) {
			s = [@"http://" stringByAppendingString:s];
		}
		[[NSUserDefaults standardUserDefaults] setObject:s forKey:kServerURLKey];
		[self loadURLString:s];
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:ac animated:YES completion:nil];
}

- (void)changeServer {
	[self promptForServerURL];
}

- (void)loadURLString:(NSString *)s {
	NSURL *url = [NSURL URLWithString:s];
	if (!url) return;
	[self.webView loadRequest:[NSURLRequest requestWithURL:url]];
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
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"无法连接"
																message:[NSString stringWithFormat:@"请检查服务器地址和网络。\n(%@)", error.localizedDescription]
														 preferredStyle:UIAlertControllerStyleAlert];
	[ac addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[self ensureServer];
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:@"修改地址" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[self changeServer];
	}]];
	[self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - WKUIDelegate (JS 弹窗转发)

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
	// 新窗口请求在当前 WebView 打开
	[webView loadRequest:navigationAction.request];
	return nil;
}

@end
