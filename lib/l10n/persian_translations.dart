// Central Persian UI catalog. Keep protocol payloads and user-entered data out of this file.
const Map<String, String> appPersianTranslations = <String, String>{
  r'''Default Theme Settings''': r'''تنظیمات پوسته پیش‌فرض''',
  r'''Custom Background''': r'''پس‌زمینه سفارشی''',
  r'''Set your own wallpaper for the default theme. You can pick a different image for day and for night — the one shown here applies to the current mode.''':
      r'''برای تم پیش‌فرض، تصویر پس‌زمینه دلخواهتان را تنظیم کنید. می‌توانید برای روز و شب تصویرهای متفاوتی انتخاب کنید؛ تصویر نمایش‌داده‌شده مربوط به حالت فعلی است.''',
  r'''Could not set background image''': r'''تنظیم تصویر پس‌زمینه ممکن نشد''',
  r'''Custom background ($modeLabel)''': r'''پس‌زمینه سفارشی ($modeLabel)''',
  r'''Tap to change your $modeLabel background''':
      r'''برای تغییر پس‌زمینه $modeLabel ضربه بزنید''',
  r'''Pick an image for the default theme ($modeLabel)''':
      r'''تصویری برای تم پیش‌فرض انتخاب کنید ($modeLabel)''',
  r'''Remove''': r'''حذف''',
  r'''Choose image''': r'''انتخاب تصویر''',
  r'''Candidate resolvers ($count)''': r'''حل‌کننده‌های پیشنهادی ($count)''',
  r'''Candidates are not verified tunnels or proof that a website opens. Copy and exports include only candidates, one IPv4:port per TXT line.''':
      r'''کاندیداها تونل‌های تأییدشده یا مدرکی برای باز شدن یک وب‌سایت نیستند. کپی و خروجی گرفتن فقط شامل کاندیداهاست؛ در هر خط یک IPv4:port.''',
  r'''Test: $_resultTarget · ${DnsScannerService.parseIp(_resultTarget) == null ? 'A lookup' : 'reverse PTR lookup'} · Port $_resultPort · Timeout $_resultTimeout ms per probe · $_resultWorkers workers${_cancel ? ' · Cancelled (partial results)' : ''}''':
      r'''آزمایش: $_resultTarget · ${DnsScannerService.parseIp(_resultTarget) == null ? 'A lookup' : 'reverse PTR lookup'} · پورت $_resultPort · مهلت $_resultTimeout میلی‌ثانیه برای هر بررسی · $_resultWorkers کارگر${_cancel ? ' · Cancelled (partial results)' : ''}''',
  r'''Copy all candidates''': r'''کپی همه موارد''',
  r'''Export TXT''': r'''خروجی TXT''',
  r'''Export JSON''': r'''خروجی JSON''',
  r'''Custom IPv4 ranges''': r'''بازه‌های سفارشی IPv4''',
  r'''Batch ${index + 1} / ${operator.batchCount} · ${operator.batchSize(index)} IPs''':
      r'''دسته ${index + 1} / ${operator.batchCount} · ${operator.batchSize(index)} IP''',
  r'''Enter your own IPv4 ranges, or choose a built-in operator above. Custom inputs use at most the first 200000 unique targets; shuffle changes their order, not the capped selection.''':
      r'''محدوده‌های IPv4 خود را وارد کنید یا اپراتور داخلی بالا را انتخاب کنید. ورودی‌های سفارشی حداکثر از ۲۰۰۰۰۰ هدف یکتا استفاده می‌کنند؛ درهم‌سازی فقط ترتیب آن‌ها را تغییر می‌دهد، نه انتخاب محدودشده را.''',
  r'''Import IPv4 ranges''': r'''درون‌ریزی بازه‌های IPv4''',
  r'''No reachable resolvers yet.''':
      r'''هنوز حل‌کننده قابل‌دسترسی پیدا نشده است.''',
  r'''Candidate resolver · UDP port $_resultPort · Tap to use''':
      r'''حل‌کننده کاندیدا · پورت UDP $_resultPort · برای استفاده ضربه بزنید''',
  r'''Not selectable · DNS capability checks incomplete or unsafe''':
      r'''قابل انتخاب نیست · بررسی قابلیت DNS ناقص یا ناامن است''',
  r'''DNS resolver discovery''': r'''یافتن حل‌کننده‌های DNS''',
  r'''Choose one IPv4 discovery approach.''':
      r'''یک روش برای یافتن IPv4 انتخاب کنید.''',
  r'''Domains use an A lookup; IPv4 targets use a reverse PTR lookup. An IP without a PTR record will not qualify. No ping or website test is used. Timeout applies to each DNS probe, not the whole scan.''':
      r'''برای دامنه‌ها از A lookup و برای هدف‌های IPv4 از reverse PTR lookup استفاده می‌شود. IP بدون رکورد PTR واجد شرایط نیست. از پینگ یا آزمایش وب‌سایت استفاده نمی‌شود. مهلت برای هر بررسی DNS است، نه کل اسکن.''',
  r'''Shuffle targets''': r'''درهم‌ریختن هدف‌ها''',
  r'''Include nearby IPv4 addresses''': r'''شامل کردن آدرس‌های IPv4 نزدیک''',
  r'''custom''': r'''سفارشی''',
  r'''Available only for custom ranges; built-in batches stay within their announced ranges.''':
      r'''فقط برای محدوده‌های سفارشی در دسترس است؛ دسته‌های داخلی در محدوده‌های اعلام‌شده خود باقی می‌مانند.''',
  r'''Expand each safe resolver to its nearby /24 addresses.''':
      r'''هر حل‌کننده امن را به نشانی‌های نزدیک آن در /24 گسترش دهید.''',
  r'''IPv6 is not supported. Only IPv4 addresses and CIDR ranges are accepted.''':
      r'''IPv6 پشتیبانی نمی‌شود. فقط آدرس‌های IPv4 و بازه‌های CIDR پذیرفته می‌شوند.''',
  r'''Scanning…''': r'''در حال اسکن…''',
  r'''Start scan''': r'''شروع اسکن''',
  r'''Tested $_tested / $_total''': r'''آزمایش‌شده $_tested / $_total''',
  r'''Operator / range source''': r'''عملگر / منبع بازه''',
  r'''Random public IPv4 count (max 200000)''':
      r'''تعداد تصادفی IPv4 عمومی (حداکثر 200000)''',
  r'''IPv4 batch (max 200000 targets)''': r'''دسته IPv4 (حداکثر 200000 هدف)''',
  r'''From IPv4''': r'''از IPv4''',
  r'''To IPv4''': r'''تا IPv4''',
  r'''Paste IPv4 addresses or CIDR ranges''':
      r'''آدرس‌های IPv4 یا بازه‌های CIDR را جای‌گذاری کنید''',
  r'''IPv4 only; separate entries with spaces, commas, or new lines.''':
      r'''فقط IPv4؛ ورودی‌ها را با فاصله، ویرگول یا خط جدید جدا کنید.''',
  r'''Imported: $_sourceLabel''': r'''واردشده: $_sourceLabel''',
  r'''Test domain or IPv4''': r'''آزمایش دامنه یا IPv4''',
  r'''Port''': r'''پورت''',
  r'''Timeout ms''': r'''مهلت زمانی برحسب میلی‌ثانیه''',
  r'''Workers (1–64)''': r'''کارگرها (1–64)''',
  r'''Copy resolver''': r'''کپی حل‌کننده''',
  r'''Stop''': r'''توقف''',
  r'''Add Custom DNS''': r'''افزودن DNS سفارشی''',
  r'''Cancel''': r'''لغو''',
  r'''Name and Primary DNS are required''': r'''نام و DNS اصلی الزامی هستند''',
  r'''Add''': r'''افزودن''',
  r'''DNS Servers''': r'''سرورهای DNS''',
  r'''Testing DNS servers...''': r'''در حال آزمایش سرورهای DNS...''',
  r'''Stop testing''': r'''توقف آزمایش''',
  r'''No DNS servers available''': r'''هیچ سرور DNS در دسترس نیست''',
  r'''Test All Servers''': r'''آزمایش همه سرورها''',
  r'''Primary: ${server.primaryDns}''': r'''اصلی: ${server.primaryDns}''',
  r'''Secondary: ${server.secondaryDns}''':
      r'''ثانویه: ${server.secondaryDns}''',
  r'''${server.ping}ms''': r'''${server.ping}ms''',
  r'''Name''': r'''نام''',
  r'''Primary DNS (required)''': r'''DNS اصلی (الزامی)''',
  r'''Secondary DNS (optional)''': r'''DNS ثانویه (اختیاری)''',
  r'''Description (optional)''': r'''توضیحات (اختیاری)''',
  r'''Test all servers''': r'''آزمایش همه سرورها''',
  r'''Wallet address copied to clipboard''':
      r'''آدرس کیف پول در کلیپ‌بورد کپی شد''',
  r'''Support Project''': r'''حمایت از پروژه''',
  r'''Support 4win VPN''': r'''حمایت از 4win VPN''',
  r'''Your support keeps our servers alive and helps us build more free tools for everyone.''':
      r'''حمایت شما سرورهای ما را فعال نگه می‌دارد و به ساخت ابزارهای رایگان بیشتر برای همه کمک می‌کند.''',
  r'''Made with passion for freedom''': r'''با عشق به آزادی ساخته شده است''',
  r'''Donate with Crypto''': r'''اهدا با رمزارز''',
  r'''TON Coin Address (TON Network):''': r'''آدرس TON Coin (شبکه TON):''',
  r'''Support us by donating any amount to keep servers active.''':
      r'''با اهدای هر مبلغی از ما حمایت کنید تا سرورها فعال بمانند.''',
  r'''Follow our GitHub''': r'''ما را در GitHub دنبال کنید''',
  r'''Watch our latest developments and contributions.''':
      r'''آخرین پیشرفت‌ها و مشارکت‌های ما را ببینید.''',
  r'''Join Community''': r'''به انجمن بپیوندید''',
  r'''Get real-time updates and support on Telegram.''':
      r'''به‌روزرسانی‌ها و پشتیبانی را لحظه‌ای در Telegram دریافت کنید.''',
  r'''Quick Guide''': r'''راهنمای سریع''',
  r'''Welcome to 4win VPN''': r'''به 4win VPN خوش آمدید''',
  r'''A full walkthrough of everything the app can do. You can reopen this guide anytime from the "?" icon at the top.''':
      r'''راهنمای کامل همه قابلیت‌های برنامه. هر زمان می‌توانید این راهنما را از آیکون "?" در بالا دوباره باز کنید.''',
  r'''Got it!''': r'''متوجه شدم!''',
  r'''4win VPN''': r'''4win VPN''',
  r'''Press & hold''': r'''فشار دهید و نگه دارید''',
  r'''Connect & disconnect''': r'''اتصال و قطع اتصال''',
  r'''Open Settings''': r'''باز کردن تنظیمات''',
  r'''Choose a protocol''': r'''یک پروتکل انتخاب کنید''',
  r'''Servers & speed testing''': r'''سرورها و آزمایش سرعت''',
  r'''Subscription links''': r'''پیوندهای اشتراک''',
  r'''Proxy protocol (SOCKS / HTTP)''': r'''پروتکل پروکسی (SOCKS / HTTP)''',
  r'''Split tunneling''': r'''تونل‌سازی انتخابی''',
  r'''Themes & appearance''': r'''تم‌ها و ظاهر''',
  r'''Connection mode (Xray)''': r'''حالت اتصال (Xray)''',
  r'''Extra tools & security''': r'''ابزارهای اضافی و امنیت''',
  r'''Staying up to date''': r'''به‌روز نگه داشتن''',
  r'''Enter Credentials''': r'''وارد کردن اطلاعات ورود''',
  r'''This config requires a username and password.''':
      r'''این پیکربندی به نام کاربری و گذرواژه نیاز دارد.''',
  r'''Username and password are required''':
      r'''نام کاربری و گذرواژه الزامی هستند''',
  r'''Connect''': r'''اتصال''',
  r'''Update notifications''': r'''اعلان‌های به‌روزرسانی''',
  r'''Would you like to receive a notification when a new version is available?''':
      r'''مایلید هنگام انتشار نسخه جدید اعلان دریافت کنید؟''',
  r'''Not now''': r'''فعلاً نه''',
  r'''Yes, notify me''': r'''بله، به من اطلاع بده''',
  r'''Loading servers...''': r'''در حال بارگذاری سرورها...''',
  r'''No strategy selected''': r'''هیچ راهبردی انتخاب نشده است''',
  r'''Strategy''': r'''راهبرد''',
  r'''Server List''': r'''فهرست سرورها''',
  r'''OpenVPN Configs''': r'''پیکربندی‌های OpenVPN''',
  r'''Resolver Scanner''': r'''اسکنر حل‌کننده''',
  r'''Slow DNS Configs''': r'''پیکربندی‌های Slow DNS''',
  r'''Proxy Servers''': r'''سرورهای پروکسی''',
  r'''Next: ${s.remark.isEmpty ? s.address : s.remark}''':
      r'''بعدی: ${s.remark.isEmpty ? s.address : s.remark}''',
  r'''Next''': r'''بعدی''',
  r'''Xray Servers''': r'''سرورهای Xray''',
  r'''Pinging…''': r'''در حال پینگ…''',
  r'''click to ping''': r'''برای پینگ کلیک کنید''',
  r'''${ping}ms''': r'''${ping}ms''',
  r'''Failed''': r'''ناموفق''',
  r'''Testing...''': r'''در حال آزمایش...''',
  r'''Settings''': r'''تنظیمات''',
  r'''How would you like to use the app?''':
      r'''دوست دارید چگونه از برنامه استفاده کنید؟''',
  r'''Simple''': r'''ساده''',
  r'''Connect with one tap; the app chooses for you.''':
      r'''با یک ضربه وصل شوید؛ برنامه خودش انتخاب می‌کند.''',
  r'''Choose protocols, servers, and detailed settings.''':
      r'''پروتکل‌ها، سرورها و تنظیمات جزئی را خودتان انتخاب کنید.''',
  r'''Switch to Advanced''': r'''رفتن به حالت پیشرفته''',
  r'''Switch to Simple''': r'''رفتن به حالت ساده''',
  r'''App Mode''': r'''حالت برنامه''',
  r'''Appearance''': r'''ظاهر''',
  r'''Light''': r'''روشن''',
  r'''Dark''': r'''تاریک''',
  r'''Disconnect''': r'''قطع اتصال''',
  r'''Could not connect with WARP, Plus, or free Xray.''':
      r'''اتصال برقرار نشد؛ اتصال WARP، Plus یا Xray رایگان ناموفق بود.''',
  r'''Are you satisfied with this connection?''':
      r'''از این اتصال راضی هستید؟''',
  r'''If not, the app will try the next available option.''':
      r'''اگر راضی نیستید، برنامه گزینهٔ بعدی را برای اتصال امتحان می‌کند.''',
  r'''Satisfied''': r'''راضی هستم''',
  r'''Change server''': r'''تغییر سرور''',
  r'''Username''': r'''نام کاربری''',
  r'''Password''': r'''گذرواژه''',
  r'''Secret Text''': r'''متن محرمانه''',
  r'''VPN Themes''': r'''پوسته‌های VPN''',
  r'''Support Us''': r'''از ما حمایت کنید''',
  r'''Select protocol''': r'''انتخاب پروتکل''',
  r'''Select protocol, current: ${_protocolName(provider.selectedProtocol)}''':
      r'''انتخاب پروتکل، فعلی: ${_protocolName(provider.selectedProtocol)}''',
  r'''Loading server list...''': r'''در حال بارگذاری فهرست سرورها...''',
  r'''Testing ${provider.servers.length} servers...''':
      r'''در حال آزمایش ${provider.servers.length} سرور...''',
  r'''Version $_appVersion''': r'''نسخه $_appVersion''',
  r'''Diagnostics''': r'''عیب‌یابی''',
  r'''Connection Logs''': r'''گزارش‌های اتصال''',
  r'''No logs yet''': r'''هنوز گزارشی وجود ندارد''',
  r'''Connect to VPN to see logs''': r'''برای دیدن گزارش‌ها به VPN متصل شوید''',
  r'''${entries.length} lines • log tail survives restarts''':
      r'''${entries.length} خط • انتهای گزارش پس از راه‌اندازی مجدد حفظ می‌شود''',
  r'''Copied ${entries.length} log lines to clipboard''':
      r'''${entries.length} خط گزارش در کلیپ‌بورد کپی شد''',
  r'''Auto-scroll ON''': r'''پیمایش خودکار روشن''',
  r'''Auto-scroll OFF''': r'''پیمایش خودکار خاموش''',
  r'''Copy all''': r'''کپی همه''',
  r'''Clear logs''': r'''پاک کردن گزارش‌ها''',
  r'''Invalid OpenVPN config. Add a remote endpoint and a client directive.''':
      r'''پیکربندی OpenVPN نامعتبر است. یک نقطه پایانی راه دور و یک دستور client اضافه کنید.''',
  r'''Failed to load configs: $e''': r'''بارگذاری پیکربندی‌ها ناموفق بود: $e''',
  r'''❌ Invalid file format. Please select .ovpn, .conf, or .open file''':
      r'''❌ قالب فایل نامعتبر است. لطفاً فایل .ovpn، .conf یا .open را انتخاب کنید''',
  r'''❌ Failed to read file: $e''': r'''❌ خواندن فایل ناموفق بود: $e''',
  r'''❌ File is empty or unreadable''':
      r'''❌ فایل خالی است یا قابل خواندن نیست''',
  r'''❌ Invalid OpenVPN config format. Missing required fields (client, remote, dev)''':
      r'''❌ قالب پیکربندی OpenVPN نامعتبر است. فیلدهای ضروری (client، remote، dev) وجود ندارند''',
  r'''❌ Platform error: ${e.message ?? e.code}''':
      r'''❌ خطای پلتفرم: ${e.message ?? e.code}''',
  r'''❌ Error: $e''': r'''❌ خطا: $e''',
  r'''Add Config''': r'''افزودن پیکربندی''',
  r'''✅ Credentials found in config file''':
      r'''✅ اطلاعات ورود در فایل پیکربندی پیدا شد''',
  r'''Name is required''': r'''نام الزامی است''',
  r'''✅ Config added successfully with embedded credentials''':
      r'''✅ پیکربندی با اطلاعات ورود داخلی با موفقیت افزوده شد''',
  r'''❌ Failed to add config (name may already exist)''':
      r'''❌ افزودن پیکربندی ناموفق بود (ممکن است نام از قبل وجود داشته باشد)''',
  r'''Config Details''': r'''جزئیات پیکربندی''',
  r'''✅ Config added successfully''': r'''✅ پیکربندی با موفقیت افزوده شد''',
  r'''Delete Config''': r'''حذف پیکربندی''',
  r'''Are you sure you want to delete "${config.name}"?''':
      r'''مطمئنید می‌خواهید «${config.name}» را حذف کنید؟''',
  r'''Delete''': r'''حذف''',
  r'''✅ Config deleted successfully''': r'''✅ پیکربندی با موفقیت حذف شد''',
  r'''❌ Failed to delete config''': r'''❌ حذف پیکربندی ناموفق بود''',
  r'''❌ No server address found in config''':
      r'''❌ نشانی سرور در پیکربندی پیدا نشد''',
  r'''Connection Test''': r'''آزمون اتصال''',
  r'''✅ Server is reachable''': r'''✅ سرور در دسترس است''',
  r'''Server: $serverAddress''': r'''سرور: $serverAddress''',
  r'''Port: $serverPort''': r'''پورت: $serverPort''',
  r'''⚡ Response Time: ${pingMs}ms''': r'''⚡ زمان پاسخ: ${pingMs}ms''',
  r'''🟢 Excellent connection''': r'''🟢 اتصال عالی''',
  r'''🟡 Good connection''': r'''🟡 اتصال خوب''',
  r'''🔴 Slow connection''': r'''🔴 اتصال کند''',
  r'''OK''': r'''تأیید''',
  r'''❌ Cannot reach server''': r'''❌ دسترسی به سرور ممکن نیست''',
  r'''Error: ${e.message}''': r'''خطا: ${e.message}''',
  r'''💡 This might be due to:
• Server is down
• Firewall blocking connection
• Wrong port number
• Internet connection issue''': r'''💡 دلیل می‌تواند یکی از این موارد باشد:
• سرور از دسترس خارج است
• فایروال اتصال را مسدود کرده است
• شماره پورت نادرست است
• مشکل اتصال اینترنت''',
  r'''⏱️ Connection timeout''': r'''⏱️ پایان مهلت اتصال''',
  r'''Server did not respond within 5 seconds. It might be slow or unreachable.''':
      r'''سرور طی ۵ ثانیه پاسخ نداد. ممکن است کند یا در دسترس نباشد.''',
  r'''❌ Test failed: $e''': r'''❌ آزمون ناموفق بود: $e''',
  r'''No OpenVPN configs''': r'''هیچ پیکربندی OpenVPN وجود ندارد''',
  r'''Tap upload icon to add .ovpn file''':
      r'''برای افزودن فایل .ovpn روی نماد بارگذاری بزنید''',
  r'''Protocol: ${config.protocol?.toUpperCase() ?? 'UDP'}''':
      r'''پروتکل: ${config.protocol?.toUpperCase() ?? 'UDP'}''',
  r'''Auth: ${config.username}''': r'''احراز هویت: ${config.username}''',
  r'''Selected''': r'''انتخاب‌شده''',
  r'''Config Name''': r'''نام پیکربندی''',
  r'''Username (Optional)''': r'''نام کاربری (اختیاری)''',
  r'''Password (Optional)''': r'''رمز عبور (اختیاری)''',
  r'''Add .ovpn File''': r'''افزودن فایل .ovpn''',
  r'''Stop test''': r'''توقف آزمون''',
  r'''Test Ping''': r'''آزمایش Ping''',
  r'''Copy proxy links''': r'''کپی پیوندهای پروکسی''',
  r'''Copy as subscription (base64)''': r'''کپی به‌عنوان اشتراک (base64)''',
  r'''Enter a valid host and port''': r'''یک میزبان و پورت معتبر وارد کنید''',
  r'''Invalid proxy: $e''': r'''پروکسی نامعتبر: $e''',
  r'''Add Proxy''': r'''افزودن پروکسی''',
  r'''SOCKS5''': r'''SOCKS5''',
  r'''SOCKS4''': r'''SOCKS4''',
  r'''HTTP''': r'''HTTP''',
  r'''Bulk import / Import group''': r'''درون‌ریزی گروهی / درون‌ریزی گروه''',
  r'''Bulk Import Proxies''': r'''درون‌ریزی گروهی پروکسی‌ها''',
  r'''Import Group''': r'''درون‌ریزی گروه''',
  r'''No proxy servers yet''': r'''هنوز سرور پروکسی وجود ندارد''',
  r'''Use Add Proxy to enter a proxy as a form, or import many proxies as a group.''':
      r'''برای وارد کردن یک پروکسی به‌صورت فرم، از افزودن پروکسی استفاده کنید؛ برای وارد کردن چند پروکسی، آن‌ها را به‌صورت یک گروه وارد کنید.''',
  r'''Selected — connects to the fastest proxy''':
      r'''انتخاب‌شده — اتصال به سریع‌ترین پروکسی''',
  r'''Tap to select • auto-picks fastest''':
      r'''برای انتخاب ضربه بزنید • سریع‌ترین به‌طور خودکار انتخاب می‌شود''',
  r'''$ping ms''': r'''$ping میلی‌ثانیه''',
  r'''Protocol''': r'''پروتکل''',
  r'''Host / IP''': r'''میزبان / IP''',
  r'''proxy.example.com''': r'''proxy.example.com''',
  r'''Username (optional)''': r'''نام کاربری (اختیاری)''',
  r'''Password (optional)''': r'''رمز عبور (اختیاری)''',
  r'''Name / Remark (optional)''': r'''نام / توضیح (اختیاری)''',
  r'''Group name''': r'''نام گروه''',
  r'''Proxy links''': r'''پیوندهای پروکسی''',
  r'''socks5://user:pass@host:1080
socks4://host:1080
http://host:8080''': r'''socks5://user:pass@host:1080
socks4://host:1080
http://host:8080''',
  r'''One proxy per line. host:port is also accepted.''':
      r'''در هر خط یک پروکسی وارد کنید. قالب host:port نیز پذیرفته می‌شود.''',
  r'''Update subscriptions''': r'''به‌روزرسانی اشتراک‌ها''',
  r'''Stop all tests''': r'''توقف همه آزمایش‌ها''',
  r'''Test all''': r'''آزمایش همه''',
  r'''Add proxy''': r'''افزودن پروکسی''',
  r'''Update group''': r'''به‌روزرسانی گروه''',
  r'''Export group''': r'''خروجی گرفتن از گروه''',
  r'''Stop group test''': r'''توقف آزمایش گروه''',
  r'''Test group''': r'''آزمایش گروه''',
  r'''Copy link''': r'''کپی پیوند''',
  r'''Ping test''': r'''آزمون پینگ''',
  r'''Open-site test''': r'''آزمون بازشدن سایت''',
  r'''$label copied''': r'''$label کپی شد''',
  r'''Turn Xray share links into protected 4win links. The output (4ws://…) imports into the Xray server list like any normal link and goes to "My Servers", but the real link stays hidden — even when copied it stays encrypted, usable only inside 4win VPN.''':
      r'''لینک‌های اشتراک Xray را به لینک‌های محافظت‌شدهٔ 4win تبدیل کنید. خروجی (4ws://…) مانند هر لینک عادی به فهرست سرور Xray وارد می‌شود و به «سرورهای من» می‌رود، اما لینک واقعی پنهان می‌ماند — حتی هنگام کپی نیز رمزگذاری‌شده باقی می‌ماند و فقط داخل 4win VPN قابل استفاده است.''',
  r'''Paste''': r'''چسباندن''',
  r'''Encrypt''': r'''رمزگذاری''',
  r'''Copy''': r'''کپی''',
  r'''Import these in Xray → Servers → Add. They cannot be turned back into the original link outside the app.''':
      r'''این‌ها را از مسیر Xray → سرورها → افزودن وارد کنید. خارج از برنامه نمی‌توان آن‌ها را به لینک اصلی برگرداند.''',
  r'''Copy secret''': r'''کپی راز''',
  r'''Only 4win VPN can decode this. Anyone without the app just sees gibberish.''':
      r'''فقط 4win VPN می‌تواند این را رمزگشایی کند. افراد بدون برنامه فقط متن نامفهوم می‌بینند.''',
  r'''Decrypt''': r'''رمزگشایی''',
  r'''Copy text''': r'''کپی متن''',
  r'''Could not decode''': r'''رمزگشایی ممکن نبود''',
  r'''Servers''': r'''سرورها''',
  r'''Retry''': r'''تلاش دوباره''',
  r'''No servers available''': r'''هیچ سروری در دسترس نیست''',
  r'''Port: ${server.port}${server.ping != null ? ' • ${server.ping}ms' : ''}''':
      r'''پورت: ${server.port}${server.ping != null ? ' • ${server.ping}ms' : ''}''',
  r'''Best server: ${provider.selectedServer!.address} (${provider.selectedServer!.ping}ms)''':
      r'''بهترین سرور: ${provider.selectedServer!.address} (${provider.selectedServer!.ping}ms)''',
  r'''Find Best Server''': r'''یافتن بهترین سرور''',
  r'''You are on the latest version (v$currentVersion)''':
      r'''شما از آخرین نسخه استفاده می‌کنید (v$currentVersion)''',
  r'''Could not check for updates. Try again later.''':
      r'''بررسی به‌روزرسانی‌ها ممکن نیست. بعداً دوباره تلاش کنید.''',
  r'''Subscription Links''': r'''پیوندهای اشتراک''',
  r'''Add subscription URLs. Their servers are merged into the free group and refreshed on every app launch.''':
      r'''نشانی‌های اینترنتی اشتراک را اضافه کنید. سرورهای آن‌ها با گروه رایگان ادغام می‌شوند و با هر بار اجرای برنامه تازه‌سازی می‌شوند.''',
  r'''No custom links added.''': r'''هیچ پیوند سفارشی‌ای اضافه نشده است.''',
  r'''Add Subscription / Link''': r'''افزودن اشتراک / پیوند''',
  r'''Subscription added & refreshed''': r'''اشتراک اضافه و تازه‌سازی شد''',
  r'''Invalid or duplicate link''': r'''لینک نامعتبر یا تکراری''',
  r'''Edit subscription''': r'''ویرایش اشتراک''',
  r'''Clear name''': r'''پاک‌کردن نام''',
  r'''Save''': r'''ذخیره''',
  r'''Invalid or duplicate URL''': r'''URL نامعتبر یا تکراری است''',
  r'''Fragment''': r'''قطعه''',
  r'''For TCP/TLS Xray links only. Splits the ClientHello while preserving the server name from the link.''':
      r'''فقط برای لینک‌های Xray از نوع TCP/TLS. ClientHello را تقسیم می‌کند و نام سرور موجود در لینک را حفظ می‌کند.''',
  r'''✂️ Xray Fragment enabled — applied on next connect''':
      r'''✂️ قطعه‌بندی Xray فعال شد — در اتصال بعدی اعمال می‌شود''',
  r'''Xray Fragment disabled''': r'''قطعه‌بندی Xray غیرفعال شد''',
  r'''Settings saved''': r'''تنظیمات ذخیره شد''',
  r'''General Settings''': r'''تنظیمات عمومی''',
  r'''${_protocolDisplayName(widget.initialProtocol!)} Settings''':
      r'''تنظیمات ${_protocolDisplayName(widget.initialProtocol!)}''',
  r'''DNS Server''': r'''سرور DNS''',
  r'''Select a DNS server''': r'''یک سرور DNS انتخاب کنید''',
  r'''Disabled while Deep Scan is on — the app tests every DNS automatically.''':
      r'''هنگام فعال بودن Deep Scan غیرفعال است — برنامه همهٔ DNSها را خودکار آزمایش می‌کند.''',
  r'''MTU''': r'''MTU''',
  r'''auto''': r'''خودکار''',
  r'''Auto: detects the best MTU (1280–1500) before connecting''':
      r'''خودکار: پیش از اتصال بهترین MTU را تشخیص می‌دهد (1280–1500)''',
  r'''manual''': r'''دستی''',
  r'''Manual: uses your value (1280–1500)''':
      r'''دستی: از مقدار شما استفاده می‌کند (1280–1500)''',
  r'''Off: default MTU (1500). Use Auto/Manual if data does not pass''':
      r'''خاموش: MTU پیش‌فرض (1500). اگر داده عبور نمی‌کند، حالت خودکار یا دستی را استفاده کنید''',
  r'''Off''': r'''خاموش''',
  r'''Auto''': r'''خودکار''',
  r'''Manual''': r'''دستی''',
  r'''⚙️ Auto MTU on — best MTU detected on connect''':
      r'''⚙️ MTU خودکار روشن است — بهترین MTU هنگام اتصال تشخیص داده شد''',
  r'''⚙️ Manual MTU on — set your value below''':
      r'''⚙️ MTU دستی روشن است — مقدار خود را در پایین تنظیم کنید''',
  r'''MTU set to default (1500)''':
      r'''MTU روی مقدار پیش‌فرض (1500) تنظیم شد''',
  r'''MTU saved: $value (applied on next connect)''':
      r'''MTU ذخیره شد: $value (در اتصال بعدی اعمال می‌شود)''',
  r'''✂️ SSTP Fragment enabled — applied on next connect''':
      r'''✂️ قطعه‌بندی SSTP فعال شد — در اتصال بعدی اعمال می‌شود''',
  r'''SSTP Fragment disabled''': r'''قطعه‌بندی SSTP غیرفعال شد''',
  r'''Deep Scan''': r'''Deep Scan''',
  r'''On: deeper scan, shorter timeout, more retries''':
      r'''روشن: اسکن عمیق‌تر، مهلت کوتاه‌تر، تلاش‌های مجدد بیشتر''',
  r'''Turn on for weak internet or heavy censorship''':
      r'''برای اینترنت ضعیف یا سانسور شدید روشن کنید''',
  r'''🔍 Deep Scan enabled — scanning more thoroughly''':
      r'''🔍 اسکن عمیق فعال شد — اسکن با دقت بیشتری انجام می‌شود''',
  r'''Deep Scan disabled''': r'''اسکن عمیق غیرفعال شد''',
  r'''Parallel Server Test''': r'''آزمایش هم‌زمان سرورها''',
  r'''How many servers are tested at once (1–300). Higher = faster but heavier.''':
      r'''تعداد سرورهایی که هم‌زمان آزمایش می‌شوند (۱–۳۰۰). مقدار بیشتر = سرعت بالاتر، اما فشار بیشتر.''',
  r'''DNS servers can be managed from the Server List screen''':
      r'''سرورهای DNS را می‌توان از صفحهٔ فهرست سرورها مدیریت کرد''',
  r'''Manage Configurations''': r'''مدیریت پیکربندی‌ها''',
  r'''Add, edit, or delete OpenVPN config files''':
      r'''افزودن، ویرایش یا حذف فایل‌های پیکربندی OpenVPN''',
  r'''Traffic Compression''': r'''فشرده‌سازی ترافیک''',
  r'''On — compresses OpenVPN traffic to save data''':
      r'''روشن — ترافیک OpenVPN را برای صرفه‌جویی در داده فشرده می‌کند''',
  r'''Compress OpenVPN traffic to save data''':
      r'''ترافیک OpenVPN را برای صرفه‌جویی در داده فشرده کنید''',
  r'''Add, edit, or delete Slow DNS configs''':
      r'''افزودن، ویرایش یا حذف پیکربندی‌های Slow DNS''',
  r'''Manage servers from the Xray Servers screen on the home page. The fragment below applies to the active Xray connection.''':
      r'''سرورها را از صفحهٔ سرورهای Xray در صفحهٔ اصلی مدیریت کنید. قطعهٔ زیر روی اتصال فعال Xray اعمال می‌شود.''',
  r'''Delay Test URL''': r'''URL آزمایش تأخیر''',
  r'''Configs are tested by actually opening THIS site through each server — both in the server list and the 3-second home-screen ping. Enter any site (e.g. https://eset.com) to check which configs can reach it. Default: http://www.google.com/gen_204''':
      r'''پیکربندی‌ها با باز کردن واقعی همین سایت از طریق هر سرور آزمایش می‌شوند — هم در فهرست سرورها و هم در پینگ ۳ثانیه‌ای صفحهٔ اصلی. هر سایتی را وارد کنید (مثلاً https://eset.com) تا ببینید کدام پیکربندی‌ها به آن دسترسی دارند. پیش‌فرض: http://www.google.com/gen_204''',
  r'''Auto (by device power)''': r'''خودکار (بر اساس توان دستگاه)''',
  r'''Automatically choose how many configs to test at once based on your phone's CPU. Stronger phones test more in parallel.''':
      r'''تعداد پیکربندی‌هایی را که هم‌زمان آزمایش می‌شوند، بر اساس CPU گوشی‌تان خودکار انتخاب می‌کند. گوشی‌های قوی‌تر پیکربندی‌های بیشتری را موازی آزمایش می‌کنند.''',
  r'''Concurrent Delay Test''': r'''آزمایش هم‌زمان تأخیر''',
  r'''How many configs to ping-test at the same time when testing a group. Higher = faster but needs a more powerful phone. Default 30, max 300.''':
      r'''تعداد پیکربندی‌هایی که هنگام آزمایش گروه هم‌زمان پینگ می‌شوند. مقدار بیشتر = سرعت بالاتر، اما به گوشی قدرتمندتری نیاز دارد. پیش‌فرض 30، حداکثر 300.''',
  r'''Group Test Rounds''': r'''دورهای آزمایش گروه''',
  r'''When you connect to a whole group, each server is re-tested this many times and the fastest one is used. Higher = more accurate best pick but slower. 1–5, default 1.''':
      r'''وقتی به یک گروه کامل متصل می‌شوید، هر سرور به این تعداد دوباره آزمایش می‌شود و سریع‌ترین سرور انتخاب می‌شود. مقدار بیشتر = انتخاب دقیق‌تر بهترین گزینه، اما کندتر. ۱–۵، پیش‌فرض ۱.''',
  r'''Connection Mode''': r'''حالت اتصال''',
  r'''Proxy mode applies to the whole app. Only the Xray protocol can run as a local proxy; SSTP, DNS Changer, OpenVPN and Slow DNS always require VPN mode.''':
      r'''حالت پروکسی روی کل برنامه اعمال می‌شود. فقط پروتکل Xray می‌تواند به‌عنوان پروکسی محلی اجرا شود؛ SSTP، DNS Changer، OpenVPN و Slow DNS همیشه به حالت VPN نیاز دارند.''',
  r'''Kill Switch''': r'''Kill Switch''',
  r'''ON: Psiphon failures blackhole traffic (no leaks) and auto-retry''':
      r'''روشن: خطاهای Psiphon ترافیک را مسدود می‌کنند (بدون نشت) و تلاش مجدد خودکار انجام می‌شود''',
  r'''OFF: Psiphon failures restore normal internet''':
      r'''خاموش: خطاهای Psiphon اینترنت عادی را بازمی‌گردانند''',
  r'''Choose apps & websites''': r'''انتخاب برنامه‌ها و وب‌سایت‌ها''',
  r'''Select apps or websites to bypass the VPN''':
      r'''برنامه‌ها یا وب‌سایت‌هایی را برای دور زدن VPN انتخاب کنید''',
  r'''Check GitHub for a newer version of 4win VPN.''':
      r'''برای نسخهٔ جدیدتر 4win VPN، GitHub را بررسی کنید.''',
  r'''Notify me when a new version is available''':
      r'''وقتی نسخهٔ جدیدی منتشر شد به من اطلاع بده''',
  r'''Notification permission is required to receive update alerts.''':
      r'''برای دریافت هشدارهای به‌روزرسانی، اجازهٔ اعلان لازم است.''',
  r'''Checking…''': r'''در حال بررسی…''',
  r'''Check for update''': r'''بررسی به‌روزرسانی''',
  r'''Save Settings''': r'''ذخیرهٔ تنظیمات''',
  r'''Rename''': r'''تغییر نام''',
  r'''Name (optional)''': r'''نام (اختیاری)''',
  r'''e.g. Germany Fast, My VPS…''': r'''مثلاً Germany Fast، My VPS…''',
  r'''Subscription URL or share link''': r'''URL اشتراک یا لینک اشتراک‌گذاری''',
  r'''https://example.com/sub.txt
or vless:// , vmess:// , trojan:// , ss://''': r'''https://example.com/sub.txt
یا vless:// ، vmess:// ، trojan:// ، ss://''',
  r'''Subscription URL''': r'''URL اشتراک''',
  r'''https://example.com/sub.txt''': r'''https://example.com/sub.txt''',
  r'''Interval (ms)''': r'''فاصلهٔ زمانی (ms)''',
  r'''SNI fallback (optional)''': r'''SNI جایگزین (اختیاری)''',
  r'''cloudflare.com''': r'''cloudflare.com''',
  r'''Packets''': r'''بسته‌ها''',
  r'''tlshello  (or 1-3)''': r'''tlshello  (یا 1-3)''',
  r'''Length (byte)''': r'''طول (بایت)''',
  r'''SSTP Settings''': r'''تنظیمات SSTP''',
  r'''Custom DNS''': r'''DNS سفارشی''',
  r'''MTU value (1280 – 1500)''': r'''مقدار MTU (1280 – 1500)''',
  r'''Lower values help when data does not pass''':
      r'''وقتی داده عبور نمی‌کند، مقادیر کمتر کمک می‌کنند''',
  r'''Save MTU''': r'''ذخیرهٔ MTU''',
  r'''DNS changer Settings''': r'''تنظیمات تغییر‌دهندهٔ DNS''',
  r'''OpenVPN Settings''': r'''تنظیمات OpenVPN''',
  r'''Slow DNS Settings''': r'''تنظیمات Slow DNS''',
  r'''Xray Settings''': r'''تنظیمات Xray''',
  r'''http://www.google.com/gen_204''': r'''http://www.google.com/gen_204''',
  r'''Reset to default''': r'''بازنشانی به پیش‌فرض''',
  r'''VPN mode''': r'''حالت VPN''',
  r'''Tunnel the whole device (system VPN)''':
      r'''کل دستگاه را تونل کنید (VPN سیستم)''',
  r'''Proxy mode''': r'''حالت پروکسی''',
  r'''Local proxy 127.0.0.1:4444 (no VPN icon) • Xray only''':
      r'''پروکسی محلی 127.0.0.1:4444 (بدون نماد VPN) • فقط Xray''',
  r'''Psiphon Settings''': r'''تنظیمات Psiphon''',
  r'''Language''': r'''زبان''',
  r'''Security''': r'''امنیت''',
  r'''Split Tunneling''': r'''تونل‌سازی تفکیک‌شده''',
  r'''Updates''': r'''به‌روزرسانی‌ها''',
  r'''About''': r'''درباره''',
  r'''Slow DNS''': r'''Slow DNS''',
  r'''Requires a dnstt server exposing a remote SOCKS5 endpoint. The client forwards TCP through tunneled DNS queries; it does not provide SSH or arbitrary UDP tunneling.''':
      r'''به یک سرور dnstt نیاز دارد که نقطهٔ پایانی SOCKS5 راه دور را ارائه کند. کلاینت، TCP را از طریق درخواست‌های DNS تونل‌شده عبور می‌دهد؛ این قابلیت SSH یا تونل‌سازی دلخواه UDP را ارائه نمی‌کند.''',
  r'''No Slow DNS configs yet''': r'''هنوز پیکربندی Slow DNS وجود ندارد''',
  r'''Tap "Add Config" to create one''':
      r'''برای ساختن یکی، روی «Add Config» بزنید''',
  r'''Domain: ${config.domain}''': r'''دامنه: ${config.domain}''',
  r'''doh''': r'''DoH''',
  r'''DoH: ${config.dohUrl}''': r'''DoH: ${config.dohUrl}''',
  r'''NS: ${config.nameServer}:${config.effectivePort}''':
      r'''NS: ${config.nameServer}:${config.effectivePort}''',
  r'''Selected: ${config.name}''': r'''انتخاب‌شده: ${config.name}''',
  r'''Delete "${config.name}"?''': r'''«${config.name}» حذف شود؟''',
  r'''Profile added''': r'''پروفایل اضافه شد''',
  r'''DNS Scanner''': r'''اسکنر DNS''',
  r'''Loading installed apps…''': r'''در حال بارگذاری برنامه‌های نصب‌شده…''',
  r'''Please wait while the app list is prepared.''':
      r'''لطفاً تا آماده شدن فهرست برنامه‌ها صبر کنید.''',
  r'''Choose how per-app tunneling works:''':
      r'''نحوهٔ تونل‌سازی برای هر برنامه را انتخاب کنید:''',
  r'''Only selected''': r'''فقط انتخاب‌شده‌ها''',
  r'''Bypass selected''': r'''دور زدن انتخاب‌شده‌ها''',
  r'''include''': r'''شامل''',
  r'''Only the checked apps will use the VPN.''':
      r'''فقط برنامه‌های علامت‌گذاری‌شده از VPN استفاده می‌کنند.''',
  r'''The checked apps will bypass the VPN.''':
      r'''برنامه‌های علامت‌زده‌شده از VPN عبور می‌کنند.''',
  r'''Websites to bypass''': r'''وب‌سایت‌های قابل دور زدن''',
  r'''No websites added''': r'''هیچ وب‌سایتی اضافه نشده است''',
  r'''Website rules apply to VPN mode across VPN protocols, including Mix, on Android 13+. They use current IP addresses; sites sharing an IP may also bypass the VPN. Reconnect after changes. Local Proxy mode and DNS Changer do not tunnel all device traffic.''':
      r'''قوانین وب‌سایت در Android 13+ برای حالت VPN و همهٔ پروتکل‌های VPN، از جمله Mix، اعمال می‌شوند. این قوانین از IPهای فعلی استفاده می‌کنند؛ سایت‌هایی که IP مشترک دارند نیز ممکن است VPN را دور بزنند. پس از تغییرات دوباره متصل شوید. حالت Local Proxy و DNS Changer تمام ترافیک دستگاه را تونل نمی‌کنند.''',
  r'''No apps found''': r'''برنامه‌ای پیدا نشد''',
  r'''name''': r'''نام''',
  r'''Loading installed apps''': r'''در حال بارگذاری برنامه‌های نصب‌شده''',
  r'''Search apps''': r'''جست‌وجوی برنامه‌ها''',
  r'''example.com or paste a website URL''':
      r'''example.com یا یک URL وب‌سایت را جای‌گذاری کنید''',
  r'''Add website''': r'''افزودن وب‌سایت''',
  r'''Night mode''': r'''حالت شب''',
  r'''Day mode''': r'''حالت روز''',
  r'''This theme uses a fixed mode''':
      r'''این پوسته از حالت ثابت استفاده می‌کند''',
  r'''Switch between light and dark''': r'''جابجایی بین حالت روشن و تاریک''',
  r'''Some themes use a fixed day/night mode, so the toggle above is disabled while they are active.''':
      r'''برخی پوسته‌ها از حالت ثابت روز/شب استفاده می‌کنند؛ بنابراین کلید بالا هنگام فعال بودن آن‌ها غیرفعال است.''',
  r'''System Default''': r'''پیش‌فرض سیستم''',
  r'''Liquid''': r'''Liquid''',
  r'''Pixel Theme 🎮''': r'''پوسته Pixel 🎮''',
  r'''Pink Theme 💕''': r'''پوسته صورتی 💕''',
  r'''Cat''': r'''گربه''',
  r'''Seasonal Themes''': r'''پوسته‌های فصلی''',
  r'''Rain · Snow · Day & Night · Autumn''':
      r'''باران · برف · روز و شب · پاییز''',
  r'''Rain Theme 🌧️''': r'''پوسته باران 🌧️''',
  r'''Snow Theme ❄️''': r'''پوسته برف ❄️''',
  r'''Day & Night''': r'''روز و شب''',
  r'''Autumn Theme 🍂''': r'''پوسته پاییز 🍂''',
  r'''Theme settings''': r'''تنظیمات پوسته''',
  r'''Export "$title" (${servers.length})''':
      r'''خروجی گرفتن از «$title» (${servers.length})''',
  r'''🔒 Encrypted servers are copied in their protected 4win form.''':
      r'''🔒 سرورهای رمزگذاری‌شده به شکل محافظت‌شدهٔ 4win کپی می‌شوند.''',
  r'''Copy share links''': r'''کپی لینک‌های اشتراک‌گذاری''',
  r'''Plain text, one link per line''': r'''متن ساده، یک لینک در هر خط''',
  r'''Paste into other apps as a sub blob''':
      r'''در برنامه‌های دیگر به‌صورت sub blob جای‌گذاری کنید''',
  r'''Edit server''': r'''ویرایش سرور''',
  r'''Edit subscription group''': r'''ویرایش گروه اشتراک''',
  r'''Delete server?''': r'''سرور حذف شود؟''',
  r'''Remove "${s.remark.isEmpty ? s.address : s.remark}"?''':
      r'''«${s.remark.isEmpty ? s.address : s.remark}» حذف شود؟''',
  r'''Delete servers from "$title"?''': r'''سرورها از «$title» حذف شوند؟''',
  r'''The group itself will remain. Choose which servers to remove.''':
      r'''خود گروه باقی می‌ماند. سرورهایی را که باید حذف شوند انتخاب کنید.''',
  r'''Delete servers without a ping''': r'''حذف سرورهای بدون پینگ''',
  r'''Delete failed or bad-ping servers''':
      r'''حذف سرورهای ناموفق یا دارای پینگ نامناسب''',
  r'''Delete all servers in this group''': r'''حذف همهٔ سرورهای این گروه''',
  r'''Add to Xray''': r'''افزودن به Xray''',
  r'''Choose a server or a subscription group''':
      r'''یک سرور یا گروه اشتراک انتخاب کنید''',
  r'''Add server''': r'''افزودن سرور''',
  r'''Paste one or more share links''':
      r'''یک یا چند لینک اشتراک‌گذاری را جای‌گذاری کنید''',
  r'''Add subscription group''': r'''افزودن گروه اشتراک''',
  r'''Add an HTTP(S) subscription URL''': r'''افزودن URL اشتراک HTTP(S)''',
  r'''Add Subscription Group''': r'''افزودن گروه اشتراک''',
  r'''Add Xray Server''': r'''افزودن سرور Xray''',
  r'''Paste one or more share links (vless://, vmess://, trojan://, ss://) or 4win encrypted links (4ws://). One per line.''':
      r'''یک یا چند لینک اشتراک (vless://، vmess://، trojan://، ss://) یا لینک رمزگذاری‌شدهٔ 4win (4ws://) را جای‌گذاری کنید. هر لینک در یک خط.''',
  r'''Added $added server${added == 1 ? '' : 's'}''':
      r'''$added سرور${added == 1 ? '' : 's'} اضافه شد''',
  r'''No valid links found''': r'''هیچ لینک معتبری پیدا نشد''',
  r'''Free servers updated ($count configs)''':
      r'''سرورهای رایگان به‌روزرسانی شدند ($count پیکربندی)''',
  r'''Could not update free servers''':
      r'''به‌روزرسانی سرورهای رایگان ممکن نبود''',
  r'''"$title" updated ($count configs)''':
      r'''"$title" به‌روزرسانی شد ($count پیکربندی)''',
  r'''Could not update "$title"''': r'''به‌روزرسانی "$title" ممکن نبود''',
  r'''Add Server''': r'''افزودن سرور''',
  r'''…and ${spec.servers.length - shown} more servers''':
      r'''…و ${spec.servers.length - shown} سرور دیگر''',
  r'''TCP ping in progress…''': r'''پینگ TCP در حال انجام است…''',
  r'''Ping in progress…''': r'''پینگ در حال انجام است…''',
  r'''Selected — connects to the fastest server''':
      r'''انتخاب شد — اتصال به سریع‌ترین سرور''',
  r'''Tap to select a server''': r'''برای انتخاب یک سرور ضربه بزنید''',
  r'''Sort by ping''': r'''مرتب‌سازی بر اساس پینگ''',
  r'''Stop URL tests''': r'''توقف آزمون‌های URL''',
  r'''URL ping all''': r'''پینگ همهٔ URLها''',
  r'''Stop TCP tests''': r'''توقف آزمون‌های TCP''',
  r'''TCP ping all''': r'''پینگ همهٔ TCPها''',
  r'''No Xray servers yet''': r'''هنوز سرور Xray وجود ندارد''',
  r'''Pull down to load free servers, or tap "Add Server" to paste a vless://, vmess://, trojan:// or ss:// share link.''':
      r'''برای بارگیری سرورهای رایگان به پایین بکشید، یا برای جای‌گذاری لینک اشتراک vless://، vmess://، trojan:// یا ss:// روی «افزودن سرور» ضربه بزنید.''',
  r'''Edit''': r'''ویرایش''',
  r'''URL ping''': r'''پینگ URL''',
  r'''TCP ping''': r'''پینگ TCP''',
  r'''Share link / configuration''': r'''لینک اشتراک‌گذاری / پیکربندی''',
  r'''Group name (optional)''': r'''نام گروه (اختیاری)''',
  r'''My subscription''': r'''اشتراک من''',
  r'''vless://...
vmess://...''': r'''vless://...
vmess://...''',
  r'''Update free servers''': r'''به‌روزرسانی سرورهای رایگان''',
  r'''Test all groups''': r'''آزمون همهٔ گروه‌ها''',
  r'''Delete selected servers''': r'''حذف سرورهای انتخاب‌شده''',
  r'''More group actions''': r'''اقدامات بیشتر گروه''',
  r'''Collapse''': r'''جمع‌کردن''',
  r'''Expand''': r'''بازکردن''',
  r'''TCP testing…''': r'''آزمون TCP…''',
  r'''Ping testing…''': r'''آزمون پینگ…''',
  r'''Ping''': r'''پینگ''',
  r'''More server actions''': r'''اقدامات بیشتر سرور''',
  r'''Delete server''': r'''حذف سرور''',
  r'''Delete strategy?''': r'''راهبرد حذف شود؟''',
  r'''Delete “${strategy.name}”?''': r'''«${strategy.name}» حذف شود؟''',
  r'''Mix Strategies''': r'''راهبردهای ترکیبی''',
  r'''${strategy.hops.length} block${strategy.hops.length == 1 ? '' : 's'}  •  ${strategy.hops.map((h) => MixStrategy.protocols[h.protocol] ?? h.protocol).join(' → ')}''':
      r'''${strategy.hops.length} بلوک${strategy.hops.length == 1 ? '' : 's'}  •  ${strategy.hops.map((h) => MixStrategy.protocols[h.protocol] ?? h.protocol).join(' → ')}''',
  r'''No Mix strategies yet''': r'''هنوز راهبرد ترکیبی وجود ندارد''',
  r'''Chain existing Xray, Proxy, and DNS profiles without changing your standalone connection.''':
      r'''پروفایل‌های موجود Xray، Proxy و DNS را بدون تغییر اتصال مستقل خود زنجیره کنید.''',
  r'''Create strategy''': r'''ایجاد راهبرد''',
  r'''New strategy''': r'''راهبرد جدید''',
  r'''Strategy actions''': r'''اقدامات راهبرد''',
  r'''warp''': r'''warp''',
  r'''No registered WARP account''': r'''هیچ حساب WARP ثبت‌شده‌ای وجود ندارد''',
  r'''Current WARP account''': r'''حساب WARP فعلی''',
  r'''Current Psiphon profile''': r'''پروفایل Psiphon فعلی''',
  r'''GROUPS''': r'''گروه‌ها''',
  r'''SERVERS''': r'''سرورها''',
  r'''New Mix Strategy''': r'''راهبرد Mix جدید''',
  r'''Edit Mix Strategy''': r'''ویرایش راهبرد Mix''',
  r'''Optional UDP-over-TLS relay''': r'''رله اختیاری UDP-over-TLS''',
  r'''Advanced: TCP-only proxy compatibility''':
      r'''پیشرفته: سازگاری با پراکسی‌های فقط TCP''',
  r'''Enable UDP relay''': r'''فعال‌سازی رله UDP''',
  r'''Not required for Psiphon: its native packet tunnel carries TCP and UDP using Psiphon servers. This optional compatibility feature is only for TCP-only proxies such as HTTP/SOCKS4 and requires your own trusted TLS relay. For wrapped proxy blocks, UDP exits from that relay while TCP still exits from the selected proxy. No relay or hidden protocol is added automatically. Standalone protocols are unchanged.''':
      r'''برای Psiphon لازم نیست: تونل بسته‌ای بومی آن، TCP و UDP را با استفاده از سرورهای Psiphon منتقل می‌کند. این قابلیت سازگاری اختیاری فقط برای پراکسی‌های صرفاً TCP مانند HTTP/SOCKS4 است و به رله TLS مورداعتماد خودتان نیاز دارد. در بلوک‌های پراکسی پوشش‌داده‌شده، UDP از آن رله خارج می‌شود و TCP همچنان از پراکسی انتخاب‌شده خارج می‌شود. هیچ رله یا پروتکل پنهانی به‌صورت خودکار اضافه نمی‌شود. پروتکل‌های مستقل بدون تغییر می‌مانند.''',
  r'''Disable relay''': r'''غیرفعال‌سازی رله''',
  r'''ADD PROTOCOL BLOCK  (${_hops.length}/${MixStrategy.maxBlocks})''':
      r'''افزودن بلوک پروتکل  (${_hops.length}/${MixStrategy.maxBlocks})''',
  r'''Tap or drag a chip to append; hold a block to reorder. DNS is a resolver at the selected position, not a tunnel: DNS first resolves on the physical link; multiple DNS blocks are allowed, and the last DNS is effective for app queries. DNS does not have to be last; tunnel order and scoped prefixes stay intact.''':
      r'''برای افزودن، روی یک تراشه بزنید یا آن را بکشید؛ برای جابه‌جایی ترتیب، یک بلوک را نگه دارید. DNS در موقعیت انتخاب‌شده یک resolver است، نه تونل: DNS ابتدا روی لینک فیزیکی resolve می‌شود؛ افزودن چند بلوک DNS مجاز است و آخرین DNS برای درخواست‌های برنامه اعمال می‌شود. DNS لازم نیست آخرین مورد باشد؛ ترتیب تونل و پیشوندهای محدوده‌دار حفظ می‌شوند.''',
  r'''Drop or add a protocol block''':
      r'''یک بلوک پروتکل را رها یا اضافه کنید''',
  r'''Maximum 50 blocks reached.''': r'''حداکثر ۵۰ بلوک مجاز است.''',
  r'''Choose DNS''': r'''انتخاب DNS''',
  r'''Choose Proxy server or group''': r'''انتخاب سرور یا گروه Proxy''',
  r'''Choose OpenVPN config''': r'''انتخاب پیکربندی OpenVPN''',
  r'''Choose WARP account''': r'''انتخاب حساب WARP''',
  r'''Choose Psiphon profile''': r'''انتخاب پروفایل Psiphon''',
  r'''Strategy name''': r'''نام راهبرد''',
  r'''e.g. Gaming route''': r'''مثلاً مسیر بازی''',
  r'''Relay host (IP or hostname)''': r'''میزبان رله (IP یا نام میزبان)''',
  r'''Relay port''': r'''پورت رله''',
  r'''TLS server name (defaults to host)''':
      r'''نام سرور TLS (به‌طور پیش‌فرض میزبان)''',
  r'''Auth token''': r'''توکن احراز هویت''',
  r'''32–256 printable ASCII characters''':
      r'''۳۲ تا ۲۵۶ نویسه قابل‌چاپ ASCII''',
  r'''START''': r'''شروع''',
  r'''This device''': r'''این دستگاه''',
  r'''INTERNET''': r'''اینترنت''',
  r'''Exit''': r'''خروج''',
  r'''Enter a valid DNS resolver and port.''':
      r'''یک resolver و پورت معتبر DNS وارد کنید.''',
  r'''Could not save profile. Check for a duplicate name and try again.''':
      r'''ذخیره پروفایل ممکن نیست. نام تکراری را بررسی و دوباره تلاش کنید.''',
  r'''Add Slow DNS Profile''': r'''افزودن پروفایل Slow DNS''',
  r'''DNSTT''': r'''DNSTT''',
  r'''DNS Transport''': r'''انتقال DNS''',
  r'''TCP resolver transport is not supported by the current DNSTT engine.''':
      r'''انتقال resolver از طریق TCP در موتور فعلی DNSTT پشتیبانی نمی‌شود.''',
  r'''Scan for Working Resolvers''': r'''جست‌وجوی resolverهای فعال''',
  r'''The scanner checks UDP resolvers; it does not verify DoT or DoH endpoints.''':
      r'''اسکنر resolverهای UDP را بررسی می‌کند؛ endpointهای DoT یا DoH را تأیید نمی‌کند.''',
  r'''Authoritative Mode''': r'''حالت Authoritative''',
  r'''Not supported by the current DNSTT engine.''':
      r'''در موتور فعلی DNSTT پشتیبانی نمی‌شود.''',
  r'''DNS Query Size''': r'''اندازه درخواست DNS''',
  r'''Managed by the engine. Custom query sizes are not supported.''':
      r'''توسط موتور مدیریت می‌شود. اندازه سفارشی درخواست پشتیبانی نمی‌شود.''',
  r'''Connection Method''': r'''روش اتصال''',
  r'''SOCKS''': r'''SOCKS''',
  r'''SSH''': r'''SSH''',
  r'''The DNSTT server must forward to a remote SOCKS5 endpoint. SSH chaining is not supported; these credentials are for SOCKS5, not SSH.''':
      r'''سرور DNSTT باید به یک endpoint راه دور SOCKS5 هدایت کند. زنجیره‌سازی SSH پشتیبانی نمی‌شود؛ این اطلاعات ورود برای SOCKS5 هستند، نه SSH.''',
  r'''Advanced''': r'''پیشرفته''',
  r'''Local Proxy''': r'''پراکسی محلی''',
  r'''The app manages the local listen address and port. Arbitrary application UDP is blocked; TCP and tunneled DNS are supported.''':
      r'''برنامه آدرس و پورت گوش‌دادن محلی را مدیریت می‌کند. UDP دلخواه برنامه‌ها مسدود است؛ TCP و DNS تونل‌شده پشتیبانی می‌شوند.''',
  r'''Save Profile''': r'''ذخیره پروفایل''',
  r'''Save profile''': r'''ذخیره پروفایل''',
  r'''Profile Name''': r'''نام پروفایل''',
  r'''Domain''': r'''دامنه''',
  r'''tunnel.example.com''': r'''tunnel.example.com''',
  r'''Public Key''': r'''کلید عمومی''',
  r'''DNS Resolver (DoH URL)''': r'''حل‌کننده DNS (نشانی DoH)''',
  r'''https://dns.example/dns-query''': r'''https://dns.example/dns-query''',
  r'''DNS Resolver''': r'''حل‌کننده DNS''',
  r'''dot''': r'''dot''',
  r'''dns.example:853''': r'''dns.example:853''',
  r'''udp''': r'''udp''',
  r'''Scanner tests UDP only''': r'''اسکنر فقط UDP را آزمایش می‌کند''',
  r'''SOCKS5 Username (optional)''': r'''نام کاربری SOCKS5 (اختیاری)''',
  r'''SOCKS5 Password (optional)''': r'''گذرواژه SOCKS5 (اختیاری)''',
  r'''Hide password''': r'''پنهان کردن گذرواژه''',
  r'''Show password''': r'''نمایش گذرواژه''',
  r'''Failover Resolvers (optional)''': r'''حل‌کننده‌های جایگزین (اختیاری)''',
  r'''Delete group?''': r'''گروه حذف شود؟''',
  r'''Delete "${group.servers.single.fullAddress}"?''':
      r'''«${group.servers.single.fullAddress}» حذف شود؟''',
  r'''Delete "${group.name}" and its servers?''':
      r'''«${group.name}» و سرورهایش حذف شوند؟''',
  r'''SSTP Servers''': r'''سرورهای SSTP''',
  r'''Add group''': r'''افزودن گروه''',
  r'''Testing $progress…''': r'''در حال آزمایش $progress…''',
  r'''Manual server selected''': r'''سرور دستی انتخاب شد''',
  r'''Selected — tap to test servers''':
      r'''انتخاب شد — برای آزمایش سرورها ضربه بزنید''',
  r'''Selected — fastest server chosen''':
      r'''انتخاب شد — سریع‌ترین سرور انتخاب شد''',
  r'''Tap to test and select fastest''':
      r'''برای آزمایش و انتخاب سریع‌ترین سرور ضربه بزنید''',
  r'''Testing…''': r'''در حال آزمایش…''',
  r'''Untested''': r'''آزمایش‌نشده''',
  r'''Unreachable''': r'''غیرقابل دسترس''',
  r'''$ping ms TCP connect''': r'''$ping میلی‌ثانیه اتصال TCP''',
  r'''No SSTP servers yet''': r'''هنوز سرور SSTP وجود ندارد''',
  r'''Add a server or group, or refresh the default group to load servers.''':
      r'''برای بارگیری سرورها، یک سرور یا گروه اضافه کنید یا گروه پیش‌فرض را تازه‌سازی کنید.''',
  r'''Add SSTP group''': r'''افزودن گروه SSTP''',
  r'''Add SSTP server''': r'''افزودن سرور SSTP''',
  r'''Refresh default servers''': r'''تازه‌سازی سرورهای پیش‌فرض''',
  r'''Add SSTP entry''': r'''افزودن ورودی SSTP''',
  r'''Test group latency''': r'''آزمایش تأخیر گروه''',
  r'''Refresh group''': r'''تازه‌سازی گروه''',
  r'''Delete group''': r'''حذف گروه''',
  r'''Test TCP latency''': r'''آزمایش تأخیر TCP''',
  r'''Host:port lines or subscription URL''':
      r'''خطوط host:port یا URL اشتراک''',
  r'''vpn.example.com:443
https://example.com/servers.txt''': r'''vpn.example.com:443
https://example.com/servers.txt''',
  r'''Host''': r'''میزبان''',
  r'''Unable to connect to Psiphon.''': r'''اتصال به Psiphon ممکن نیست.''',
  r'''Unable to connect: $error''': r'''اتصال ممکن نیست: $error''',
  r'''Psiphon servers''': r'''سرورهای Psiphon''',
  r'''TCP reachability, not VPN latency. A successful test does not guarantee a Psiphon connection.''':
      r'''دسترسی‌پذیری TCP، نه تأخیر VPN. موفقیت آزمایش، اتصال Psiphon را تضمین نمی‌کند.''',
  r'''Test all (max 4 at a time)''': r'''آزمایش همه (حداکثر ۴ مورد هم‌زمان)''',
  r'''The selected server is no longer listed. Choose another server or Automatic.''':
      r'''سرور انتخاب‌شده دیگر در فهرست نیست. سرور دیگری یا «خودکار» را انتخاب کنید.''',
  r'''Automatic selection''': r'''انتخاب خودکار''',
  r'''Let Psiphon choose a server''': r'''انتخاب سرور را به Psiphon بسپارید''',
  r'''No servers available.''': r'''هیچ سروری در دسترس نیست.''',
  r'''Refresh signed list''': r'''تازه‌سازی فهرست امضاشده''',
  r'''Search IP or region''': r'''جست‌وجوی IP یا منطقه''',
  r'''Sort by TCP latency''': r'''مرتب‌سازی بر اساس تأخیر TCP''',
  r'''English''': r'''انگلیسی''',
  r'''Select Protocol''': r'''انتخاب پروتکل''',
  r'''Choose your connection''': r'''اتصال خود را انتخاب کنید''',
  r'''$title settings''': r'''تنظیمات $title''',
  r'''Close protocol selector''': r'''بستن انتخاب‌گر پروتکل''',
  r'''General settings (all protocols)''': r'''تنظیمات عمومی (همه پروتکل‌ها)''',
  r'''General''': r'''عمومی''',
  r'''This protocol has no additional settings on this page.''':
      r'''برای این پروتکل، تنظیمات اضافه‌ای در این صفحه وجود ندارد.''',
  r'''Mix''': r'''Mix''',
  r'''Ordered, real multi-hop strategies''':
      r'''راهبردهای چندجهشی واقعی و مرتب‌شده''',
  r'''Xray''': r'''Xray''',
  r'''Real Xray core + TLS fragment''': r'''هسته واقعی Xray + قطعه‌بندی TLS''',
  r'''Psiphon''': r'''Psiphon''',
  r'''Automatic server selection''': r'''انتخاب خودکار سرور''',
  r'''WARP''': r'''WARP''',
  r'''Cloudflare WireGuard tunnel''': r'''تونل WireGuard کلادفلر''',
  r'''OpenVPN''': r'''OpenVPN''',
  r'''Custom config support''': r'''پشتیبانی از پیکربندی سفارشی''',
  r'''SSTP''': r'''SSTP''',
  r'''DNS changer''': r'''تغییردهنده DNS''',
  r'''Connect via DNS servers''': r'''اتصال از طریق سرورهای DNS''',
  r'''Proxy''': r'''Proxy''',
  r'''SOCKS4 / SOCKS5 / HTTP proxy''': r'''پروکسی SOCKS4 / SOCKS5 / HTTP''',
  r'''DNS Tunneling for heavy censorship''':
      r'''تونل‌سازی DNS برای سانسور شدید''',
  r'''New update available''': r'''نسخه جدیدی برای به‌روزرسانی موجود است''',
  r'''Your current version: ${widget.currentVersion}''':
      r'''نسخه فعلی شما: ${widget.currentVersion}''',
  r'''New version: ${widget.updateInfo.latestVersion}''':
      r'''نسخه جدید: ${widget.updateInfo.latestVersion}''',
  r'''Changes:''': r'''تغییرات:''',
  r'''Downloading... ${(_progress * 100).toStringAsFixed(0)}%''':
      r'''در حال دانلود... ${(_progress * 100).toStringAsFixed(0)}٪''',
  r'''Downloading...''': r'''در حال دانلود...''',
  r'''Later''': r'''بعداً''',
  r'''Download''': r'''دانلود''',
  r'''Loading''': r'''در حال بارگذاری''',
  r'''Psiphon server list''': r'''فهرست سرورهای Psiphon''',
  r'''Open''': r'''باز کردن''',
  r'''A signed-list refresh is already in progress.''':
      r'''تازه‌سازی فهرست امضاشده از قبل در حال انجام است.''',
  r'''The signed server list was not updated.''':
      r'''فهرست سرورهای امضاشده به‌روزرسانی نشد.''',
  r'''Initialized does not prove remote reachability.''':
      r'''راه‌اندازی‌شدن، دسترسی‌پذیری راه دور را ثابت نمی‌کند.''',
  r'''View failed chain''': r'''مشاهده زنجیره ناموفق''',
  r'''View Mix chain''': r'''مشاهده زنجیره Mix''',
  r'''Start''': r'''شروع''',
  r'''Connected''': r'''متصل''',
  r'''Failure detected at block ${diagnostics.states.indexOf(MixBlockState.failed) + 1}''':
      r'''خرابی در بلوک ${diagnostics.states.indexOf(MixBlockState.failed) + 1} شناسایی شد''',
  r'''Failure location unknown''': r'''محل خرابی نامشخص است''',
  r'''Close chain graph''': r'''بستن نمودار زنجیره''',
  r'''Cat mascot''': r'''نماد گربه''',
  r'''${data.displayName} connection stages''':
      r'''مراحل اتصال ${data.displayName}''',
  r'''Only observed signals are marked complete. A running service does not always prove remote reachability.''':
      r'''فقط سیگنال‌های مشاهده‌شده کامل علامت‌گذاری می‌شوند. فعال بودن یک سرویس همیشه دسترسی‌پذیری از راه دور را ثابت نمی‌کند.''',
  r'''Close connection graph''': r'''بستن نمودار اتصال''',
  r'''Choose your language''': r'''زبان خود را انتخاب کنید''',
  r'''Select the language used in the app interface.''':
      r'''زبان مورد استفاده در رابط برنامه را انتخاب کنید.''',
  r'''Disconnect before changing the Psiphon server.''':
      r'''پیش از تغییر سرور Psiphon اتصال را قطع کنید.''',
  r'''SSTP connection lost. Select another server or retry.''':
      r'''اتصال SSTP قطع شد. سرور دیگری انتخاب کنید یا دوباره تلاش کنید.''',
  r'''SSTP connection failed. Select another server or retry.''':
      r'''اتصال SSTP ناموفق بود. سرور دیگری انتخاب کنید یا دوباره تلاش کنید.''',
  r'''Proxy mode only supports Xray. Switch to the Xray protocol, ''':
      r'''حالت پروکسی فقط از Xray پشتیبانی می‌کند. به پروتکل Xray تغییر دهید،''',
  r'''or turn on VPN mode in Settings to use this protocol.''':
      r'''یا برای استفاده از این پروتکل، حالت VPN را در تنظیمات روشن کنید.''',
  r'''Retrying… (attempt ${attempt + 1}/${policy.maxAttempts})''':
      r'''تلاش مجدد… (تلاش ${attempt + 1}/${policy.maxAttempts})''',
  r'''$failure — kill switch active, traffic blocked. Retry or disconnect.''':
      r'''$failure — کلید قطع اضطراری فعال است و ترافیک مسدود شده. دوباره تلاش کنید یا اتصال را قطع کنید.''',
  r'''$failure — VPN service remains active. Retry or disconnect.''':
      r'''$failure — سرویس VPN همچنان فعال است. دوباره تلاش کنید یا اتصال را قطع کنید.''',
  r'''Psiphon connection failed: $e''': r'''اتصال Psiphon ناموفق بود: $e''',
  r'''Psiphon connection lost''': r'''اتصال Psiphon قطع شد''',
  r'''Connection unstable — retrying (attempt $_psiphonFailCount)…''':
      r'''اتصال ناپایدار است — تلاش مجدد (تلاش $_psiphonFailCount)…''',
  r'''Please select a DNS server from Server List first''':
      r'''ابتدا یک سرور DNS از فهرست سرورها انتخاب کنید''',
  r'''Please select an OpenVPN config first''':
      r'''ابتدا یک پیکربندی OpenVPN انتخاب کنید''',
  r'''Authentication failed. Wrong username or password.''':
      r'''احراز هویت ناموفق بود. نام کاربری یا رمز عبور نادرست است.''',
  r'''Please select a Slow DNS config first''':
      r'''ابتدا یک پیکربندی Slow DNS انتخاب کنید''',
  r'''Approve the VPN permission, then connect again.''':
      r'''مجوز VPN را تأیید کنید، سپس دوباره متصل شوید.''',
  r'''Please add and select a proxy server first''':
      r'''ابتدا یک سرور پروکسی اضافه و انتخاب کنید''',
  r'''No working proxy found in this group. Try again.''':
      r'''پروکسی فعالی در این گروه پیدا نشد. دوباره تلاش کنید.''',
  r'''VPN permission denied''': r'''مجوز VPN رد شد''',
  r'''Failed to start proxy connection''': r'''شروع اتصال پروکسی ناموفق بود''',
  r'''Failed to connect: ${e.toString()}''':
      r'''اتصال ناموفق بود: ${e.toString()}''',
  r'''Please add and select an Xray server first''':
      r'''ابتدا یک سرور Xray اضافه و انتخاب کنید''',
  r'''No working server found in this group. Try again.''':
      r'''سرور فعالی در این گروه پیدا نشد. دوباره تلاش کنید.''',
  r'''No reachable Xray servers found. Check your internet connection and try again.''':
      r'''هیچ سرور Xray قابل‌دسترسی پیدا نشد. اتصال اینترنت خود را بررسی و دوباره تلاش کنید.''',
  r'''Failed to start Xray core''': r'''شروع هسته Xray ناموفق بود''',
  r'''Disconnect Mix before editing the active strategy.''':
      r'''پیش از ویرایش راهبرد فعال، Mix را قطع کنید.''',
  r'''Strategy not found.''': r'''راهبرد پیدا نشد.''',
  r'''Open Strategy and select a Mix strategy first.''':
      r'''راهبرد را باز کنید و ابتدا یک راهبرد Mix انتخاب کنید.''',
  r'''Mix requires VPN mode. Change Connection mode in Settings.''':
      r'''Mix به حالت VPN نیاز دارد. حالت اتصال را در تنظیمات تغییر دهید.''',
  r'''Grant VPN permission, then tap Connect again.''':
      r'''مجوز VPN را بدهید، سپس دوباره روی اتصال بزنید.''',
  r'''Could not start Mix.''': r'''شروع Mix ممکن نبود.''',
  r'''The complete chain failed its connection test. No tunnel was started.''':
      r'''آزمون اتصال زنجیره کامل ناموفق بود. هیچ تونلی شروع نشد.''',
  r'''Mix core did not become ready.''': r'''هسته Mix آماده نشد.''',
  r'''Mix tunnel stopped. Reconnect to retry the entire chain.''':
      r'''تونل Mix متوقف شد. برای تلاش دوباره در کل زنجیره متصل شوید.''',
  r'''Disconnect before changing SSTP servers.''':
      r'''پیش از تغییر سرورهای SSTP اتصال را قطع کنید.''',
  r'''Wait for the SSTP operation to finish.''':
      r'''تا پایان عملیات SSTP صبر کنید.''',
  r'''Could not load SSTP servers. Refresh to try again.''':
      r'''بارگیری سرورهای SSTP ممکن نبود. برای تلاش دوباره تازه‌سازی کنید.''',
  r'''SSTP group not found.''': r'''گروه SSTP پیدا نشد.''',
  r'''SSTP server not found.''': r'''سرور SSTP پیدا نشد.''',
  r'''No reachable SSTP servers. Refresh or choose another group.''':
      r'''هیچ سرور SSTP قابل دسترسی نیست. تازه‌سازی کنید یا گروه دیگری انتخاب کنید.''',
  r'''Failed to connect to SSTP servers. Select another target or retry.''':
      r'''اتصال به سرورهای SSTP ناموفق بود. هدف دیگری انتخاب کنید یا دوباره تلاش کنید.''',
  r'''SSTP connection failed. Select another target or retry.''':
      r'''اتصال SSTP ناموفق بود. هدف دیگری انتخاب کنید یا دوباره تلاش کنید.''',
  r'''Native scanner returned an invalid IP''':
      r'''اسکنر بومی یک IP نامعتبر برگرداند''',
  r'''Port must be between 1 and 65535.''':
      r'''پورت باید بین 1 و 65535 باشد.''',
  r'''Timeout must be between 100 and 10000 ms.''':
      r'''مهلت زمانی باید بین 100 و 10000 ms باشد.''',
  r'''Unexpected scanner response''': r'''پاسخ غیرمنتظره از اسکنر''',
  r'''Invalid IP or CIDR: $token''': r'''IP یا CIDR نامعتبر: $token''',
  r'''Enter a valid DNS probe domain or IPv4 address, not a URL or IPv6 address.''':
      r'''یک دامنه معتبر برای کاوش DNS یا آدرس IPv4 وارد کنید، نه URL یا آدرس IPv6.''',
  r'''Enter a valid IPv4 address or DNS probe domain.''':
      r'''یک آدرس IPv4 معتبر یا دامنهٔ کاوش DNS وارد کنید.''',
  r'''Enter a valid DNS probe domain.''':
      r'''یک دامنهٔ معتبر برای کاوش DNS وارد کنید.''',
  r'''Not a 4win server link''': r'''پیوند سرور 4win نیست''',
  r'''Empty input''': r'''ورودی خالی است''',
  r'''Not a 4win secret (missing prefix)''':
      r'''این secret مربوط به 4win نیست (پیشوند وجود ندارد)''',
  r'''Corrupted secret''': r'''secret خراب است''',
  r'''Wrong key or corrupted secret''':
      r'''کلید اشتباه است یا secret خراب شده است''',
  r'''Invalid character''': r'''کاراکتر نامعتبر است''',
  r'''Failed to load servers: ${response.statusCode}''':
      r'''بارگذاری سرورها ناموفق بود: ${response.statusCode}''',
  r'''WARP registration failed: HTTP ${resp.statusCode} ${resp.body}''':
      r'''ثبت WARP ناموفق بود: HTTP ${resp.statusCode} ${resp.body}''',
  r'''WARP registration response has no peers''':
      r'''پاسخ ثبت WARP فاقد peer است''',
  r'''WARP registration response missing required fields''':
      r'''فیلدهای لازم در پاسخ ثبت WARP وجود ندارند''',
  r'''Invalid Psiphon SOCKS port''': r'''پورت SOCKS سایفون نامعتبر است''',
  r'''WARP key must decode to 32 bytes''':
      r'''کلید WARP باید به 32 بایت decode شود''',
  r'''Invalid WARP key encoding''': r'''کدگذاری کلید WARP نامعتبر است''',
  r'''WARP account is missing an address or peer''':
      r'''حساب WARP فاقد address یا peer است''',
  r'''WARP reserved bytes must contain 3 bytes''':
      r'''بایت‌های رزروشدهٔ WARP باید شامل 3 بایت باشند''',
  r'''TLS ClientHello fragment length must be at least 6 bytes.''':
      r'''طول قطعهٔ TLS ClientHello باید حداقل 6 بایت باشد.''',
  r'''Invalid Fragment $field. Use an integer or an inclusive range.''':
      r'''Fragment $field نامعتبر است. از یک عدد صحیح یا یک بازهٔ شامل دو سر استفاده کنید.''',
  r'''Invalid Fragment $field range.''':
      r'''بازهٔ Fragment $field نامعتبر است.''',
  r'''Unsupported protocol: ${server.protocol}''':
      r'''پروتکل پشتیبانی‌نشده: ${server.protocol}''',
  r'''XHTTP extra must be a JSON object''':
      r'''XHTTP extra باید یک شیء JSON باشد''',
  r'''The native Mix coordinator returned an invalid response.''':
      r'''هماهنگ‌کنندهٔ بومی Mix پاسخی نامعتبر برگرداند.''',
  r'''The complete Mix chain failed.''': r'''اتصال کامل Mix ناموفق بود.''',
  r'''This app build does not include the Mix coordinator.''':
      r'''این نسخهٔ برنامه هماهنگ‌کنندهٔ Mix را ندارد.''',
  r'''Mix DNS must be an IP address.''':
      r'''DNS مربوط به Mix باید یک آدرس IP باشد.''',
  r'''Mix supports SOCKS5 and HTTP proxies, not SOCKS4.''':
      r'''Mix از پراکسی‌های SOCKS5 و HTTP پشتیبانی می‌کند، نه SOCKS4.''',
  r'''Unsupported Mix block.''': r'''بلوک Mix پشتیبانی نمی‌شود.''',
  r'''Could not save Mix strategies.''':
      r'''ذخیرهٔ راهبردهای Mix ناموفق بود.''',
  r'''Could not save the selected Mix strategy.''':
      r'''ذخیرهٔ راهبرد انتخاب‌شدهٔ Mix ناموفق بود.''',
  r'''WARP Mix reference must be the default account.''':
      r'''مرجع WARP Mix باید حساب پیش‌فرض باشد.''',
  r'''No WARP account is registered.''': r'''هیچ حساب WARPای ثبت نشده است.''',
  r'''Psiphon Mix reference must be the default profile.''':
      r'''مرجع Psiphon Mix باید نمایهٔ پیش‌فرض باشد.''',
  r'''Unsupported Mix block: ${hop.protocol}''':
      r'''بلوک Mix پشتیبانی‌نشده: ${hop.protocol}''',
  r'''SSTP server/group reference is missing. Edit this strategy.''':
      r'''مرجع سرور/گروه SSTP وجود ندارد. این راهبرد را ویرایش کنید.''',
  r'''$label reference is missing. Edit this strategy.''':
      r'''مرجع $label وجود ندارد. این راهبرد را ویرایش کنید.''',
  r'''DNS resolver reference is missing. Edit this strategy.''':
      r'''مرجع حل‌کنندهٔ DNS وجود ندارد. این راهبرد را ویرایش کنید.''',
  r'''No resolver established an authenticated Slow DNS tunnel.''':
      r'''هیچ resolverی یک تونل Slow DNS احراز‌شده برقرار نکرد.''',
  r'''An operator catalog must contain IPv4 addresses.''':
      r'''کاتالوگ operator باید شامل آدرس‌های IPv4 باشد.''',
  r'''Catalog ranges ended before batch $zeroBasedIndex was filled.''':
      r'''بازه‌های کاتالوگ پیش از تکمیل batch $zeroBasedIndex تمام شدند.''',
  r'''ranges must not be empty''': r'''ranges نباید خالی باشد''',
  r'''ranges must be [start, end]''':
      r'''ranges باید به‌شکل [start, end] باشد''',
  r'''range is outside IPv4 or is reversed''':
      r'''range خارج از IPv4 است یا برعکس وارد شده است''',
  r'''ranges must be sorted and disjoint''':
      r'''ranges باید مرتب و مجزا باشند''',
  r'''Failed to refresh server group: ${response.statusCode}''':
      r'''تازه‌سازی گروه سرور ناموفق بود: ${response.statusCode}''',
  r'''The subscription contains no valid servers.''':
      r'''اشتراک هیچ سرور معتبری ندارد.''',
  r'''Subscription URL has no host.''': r'''URL اشتراک host ندارد.''',
  r'''Failed to load subscription: ${response.statusCode}''':
      r'''بارگذاری اشتراک ناموفق بود: ${response.statusCode}''',
  r'''No valid SSTP servers found.''': r'''هیچ سرور SSTP معتبری پیدا نشد.''',
  r'''Username and password are required.''':
      r'''نام کاربری و گذرواژه الزامی هستند.''',
  r'''Enter a valid server host.''': r'''یک host معتبر برای سرور وارد کنید.''',
  r'''The built-in server group cannot be deleted.''':
      r'''گروه سرور داخلی را نمی‌توان حذف کرد.''',
  r'''Could not save SSTP server groups.''':
      r'''ذخیرهٔ گروه‌های سرور SSTP ممکن نیست.''',
  r'''Proxy mode only supports Xray. Switch to the Xray protocol, or turn on VPN mode in Settings to use this protocol.''':
      r'''حالت پروکسی فقط از Xray پشتیبانی می‌کند. پروتکل Xray را انتخاب کنید یا برای استفاده از این پروتکل، حالت VPN را در تنظیمات روشن کنید.''',
  r'''Connecting...''': r'''در حال اتصال...''',
  r'''Disconnecting...''': r'''در حال قطع اتصال...''',
  r'''Disconnected''': r'''اتصال قطع است''',
  r'''Error''': r'''خطا''',
  r'''🔒 WARP Connected''': r'''🔒 WARP متصل است''',
  r'''🔒 Xray Connected''': r'''🔒 Xray متصل است''',
  r'''Tap to open • Reconnect or disconnect''':
      r'''برای باز کردن بزنید • اتصال مجدد یا قطع اتصال''',
  r'''Local proxy running • Reconnect or disconnect''':
      r'''پراکسی محلی فعال است • اتصال مجدد یا قطع اتصال''',
  r'''Psiphon traffic bridge active''': r'''پل ترافیک Psiphon فعال است''',
  r'''Preparing an isolated tunnel stage''':
      r'''در حال آماده‌سازی یک مرحلهٔ مستقل تونل''',
  r'''Preparing the complete chain''': r'''در حال آماده‌سازی زنجیرهٔ کامل''',
  r'''Testing the complete chain''': r'''در حال آزمایش زنجیرهٔ کامل''',
  r'''Reconnecting the complete chain''':
      r'''در حال اتصال مجدد به زنجیرهٔ کامل''',
  r'''Connecting; traffic is blocked until ready''':
      r'''در حال اتصال؛ تا آماده‌شدن، ترافیک مسدود است''',
  r'''Reconnecting; traffic is blocked until ready''':
      r'''در حال اتصال مجدد؛ تا آماده‌شدن، ترافیک مسدود است''',
  r'''Connection failed; traffic is blocked''':
      r'''اتصال ناموفق بود؛ ترافیک مسدود است''',
  r'''Connection failed; VPN not started''':
      r'''اتصال ناموفق بود؛ VPN راه‌اندازی نشد''',
  r'''Connecting to Psiphon...''': r'''در حال اتصال به Psiphon...''',
  r'''Reconnecting to Psiphon...''': r'''در حال اتصال مجدد به Psiphon...''',
  r'''Psiphon is starting...''': r'''Psiphon در حال راه‌اندازی است...''',
  r'''Reconnecting — traffic blocked''':
      r'''در حال اتصال مجدد — ترافیک مسدود است''',
  r'''Psiphon core up — starting traffic bridge...''':
      r'''هستهٔ Psiphon آماده است — در حال راه‌اندازی پل ترافیک...''',
  r'''Waiting for network...''': r'''در انتظار شبکه...''',
  r'''Connected to Psiphon''': r'''به Psiphon متصل شد''',
  r'''Connected to $region''': r'''به $region متصل شد''',
  r'''Connected via $resolver''': r'''از طریق $resolver متصل شد''',
  r'''Psiphon bridge failed to start''':
      r'''راه‌اندازی پل Psiphon ناموفق بود''',
  r'''Psiphon bridge failed to start: $detail''':
      r'''راه‌اندازی پل Psiphon ناموفق بود: $detail''',
  r'''Psiphon traffic bridge failed''': r'''پل ترافیک Psiphon ناموفق بود''',
  r'''Psiphon traffic bridge failed: $detail''':
      r'''پل ترافیک Psiphon ناموفق بود: $detail''',
  r'''Psiphon failed: $failure''': r'''اتصال Psiphon ناموفق بود: $failure''',
  r'''Psiphon failed: $reason — traffic blocked by kill switch''':
      r'''خطای Psiphon: $reason — ترافیک با کلید قطع اضطراری مسدود شد''',
  r'''Connecting stage $stage of $total''':
      r'''در حال اتصال به مرحلهٔ $stage از $total''',
  r'''$count stages active''': r'''$count مرحله فعال''',
  r'''$count stages active · TCP-only''': r'''$count مرحله فعال · فقط TCP''',
  r'''Version $version is ready to install.''':
      r'''نسخهٔ $version برای نصب آماده است.''',
  r'''DNS: $dns • Speed unavailable (DNS-only)''':
      r'''DNS: $dns • سرعت در دسترس نیست (فقط DNS)''',
  r'''DNS: $dns • Reconnect or disconnect''':
      r'''DNS: $dns • اتصال مجدد یا قطع اتصال''',
  r'''INVALID SETTING: $message''': r'''تنظیم نامعتبر: $message''',
  r'''Hostname is missing''': r'''نام میزبان وارد نشده است.''',
  r'''The given port is out of 0-65535''':
      r'''شمارهٔ درگاه باید بین 0 تا 65535 باشد.''',
  r'''Adding trusted certificates needs SSL version to be specified''':
      r'''برای افزودن گواهی‌های مورد اعتماد، باید نسخهٔ SSL مشخص شود.''',
  r'''No certificates directory was selected''':
      r'''پوشهٔ گواهی‌ها انتخاب نشده است.''',
  r'''No cipher suite was selected''':
      r'''هیچ مجموعهٔ رمزنگاری انتخاب نشده است.''',
  r'''Proxy server hostname is missing''':
      r'''نام میزبان پراکسی وارد نشده است.''',
  r'''The given proxy server port is out of 0-65535''':
      r'''شمارهٔ درگاه پراکسی باید بین 0 تا 65535 باشد.''',
  r'''The given MRU is out of $min-$max''':
      r'''مقدار MRU باید در بازهٔ $min تا $max باشد.''',
  r'''No network protocol was enabled''':
      r'''هیچ پروتکل شبکه‌ای فعال نشده است.''',
  r'''No static IPv4 address was given''':
      r'''نشانی ثابت IPv4 وارد نشده است.''',
  r'''No authentication protocol was enabled''':
      r'''هیچ پروتکل احراز هویتی فعال نشده است.''',
  r'''PPP authentication timeout period must be >=1 second''':
      r'''مهلت احراز هویت PPP باید دست‌کم 1 ثانیه باشد.''',
  r'''No custom DNS server address was given''':
      r'''نشانی سرور DNS سفارشی وارد نشده است.''',
  r'''Retry Count must be a positive integer''':
      r'''تعداد تلاش مجدد باید عدد صحیح مثبت باشد.''',
  r'''No log directory was selected''': r'''پوشهٔ گزارش انتخاب نشده است.''',
  r'''Download: $download • Upload: $upload''':
      r'''دریافت: $download • ارسال: $upload''',
};
