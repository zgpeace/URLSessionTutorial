# URLSession实现iTunes搜索听歌
语言: swift, 版本：4.2，XCode：10.1<br>
写作时间：2019-02-16
# 说明
本文实现功能：
用URLSession创建http请求 > 搜索iTunes里面的歌曲列表 > 点击下载歌曲(可暂停、还原、取消下载操作) > background 下载歌曲 > 播放歌曲。

这里接力于[iTunes Search API](https://affiliate.itunes.apple.com/resources/documentation/itunes-store-web-service-search-api/)， 允许搜索歌曲，并播放30秒的预览歌曲。

# URLSession功能概览
URLSession以及一系列类实现HTTP/HTTPS请求。详情请参考[URLSession官方文档](https://developer.apple.com/documentation/foundation/urlsession)
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190214095206939.png)
>URLSessionConfiguration

URLSession实现发送和接收HTTP请求. 你创建URLSession通过配置URLSessionConfiguration, URLSessionConfiguration主要有三个属性:

- .default: 创建一个默认的配置对象，实现硬盘全局持久化的缓存cache, 证书credential，和cookie存储对象.
- .ephemeral: 类似于.default的默认配置, 不同点在于相关session数据是存储在内存. 
- .background: session在实现上传、下载任务的时候在background. 传输继续即使app被系统挂起suspended，终结terminated.

URLSessionConfiguration也可以配置session properties，比如超时timeout values, 缓存策略caching policies，和额外的additional HTTP headers. 更多信息请参照[URLSessionConfiguration官方文档](https://developer.apple.com/documentation/foundation/urlsessionconfiguration).

> URLSessionTask

URLSessionTask是一个抽象类，表示一个任务对象. 一个session创建一个活多个tasks去做具体的工作，比如获取数据fetching data，下载或者上传文件 files.

有3个实体类session tasks:
- URLSessionDataTask: 用于HTTP GET请求去服务器获取数据到内存.
- URLSessionUploadTask: 用于把本地硬盘文件上传到web service, 通常通过HTTP POST 或者 PUT方法.
- URLSessionDownloadTask: 用于从远处服务remote service下载文件到本地临时沙盒.
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190214103512755.png)
你可以暂停suspend, 恢复resume 和 取消cancel 任务tasks. URLSessionDownloadTask还有额外的能力：为未来恢复future resumption设置暂停.

通常, URLSession返回结果又两种方式: block方式completion handler, 或者是代理方法的方式（在创建session的时候设置delegate）.

以上就是URLSession的概览，下面就开始实践了。


# 🌰栗子工程下载
点击[下载初始栗子工程](https://koenig-media.raywenderlich.com/uploads/2017/06/HalfTunes-Starter-1.zip)，它已经实现用api搜索歌曲，展示歌曲列表，网络服务类，辅助方法存储下载的歌曲，播放歌曲。这样子可以专注于实现网络特性去完善工程。栗子运行界面：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190214094831516.png)
# Data Task
创建Data Task，调用iTunes Search API去查询iTunes歌曲。

`SearchVC+SearchBarDelegate.swift` 的方法 `searchBarSearchButtonClicked(_:)` 在status bar转菊花，表示正在网络请求. 有结果返回的时候调用方法 `getSearchResults(searchTerm:completion:)` , 在类中 `QueryService.swift`.

首先，在类 `Networking/QueryService.swift` , 替换第一个// TODO 为下面代码:
```swift
// 1
let defaultSession = URLSession(configuration: .default)
// 2
var dataTask: URLSessionDataTask?

```
代码解析：
1. 创建URLSession，并初始化为default configuration。
2. 称明变量URLSessionDataTask, 当用户搜索的时候， 它用于HTTP GET 请求 iTunes Search web service网络服务. 每次用户搜索新的字符串，data task都会被重新初始化.

接下来，替换方法 `getSearchResults(searchTerm:completion:)` 为以下内容:
```swift
func getSearchResults(searchTerm: String, completion: @escaping QueryResult) {
  // 1
  dataTask?.cancel()
  // 2
  if var urlComponents = URLComponents(string: "https://itunes.apple.com/search") {
    urlComponents.query = "media=music&entity=song&term=\(searchTerm)"
    // 3
    guard let url = urlComponents.url else { return }
    // 4
    dataTask = defaultSession.dataTask(with: url, completionHandler: { (data, response, error) in
      defer { self.dataTask = nil }
      // 5
      if let error = error {
        self.errorMessage += "DataTask error: " + error.localizedDescription + "\n"
      } else if let data = data,
          let response = response as? HTTPURLResponse,
        response.statusCode == 200 {
        
        self.updateSearchResults(data)
        // 6
        DispatchQueue.main.async {
          completion(self.tracks, self.errorMessage)
        }
      }
    })
    
    // 7
    dataTask?.resume()
  }
}

```
代码解析：
1. 每次搜索之前，先取消data task(如果已经存在) , 因为需要复用data task去做新的搜索.
2. 创建URLComponents对象，设置搜索url，并拼接搜索参数.
3. urlComponents的url属性可能为nil, 为nil则退出.
4. 从创建session起, 初始化URLSessionDataTask，参数有url，和一个回调completion handler(当data task完成的时候被访问).
5. 如果HTTP请求成功, 调用辅助方法 `updateSearchResults(_:)` , 它解析response data到tracks array.
6. 切换到主队列main queue传递数组tracks到completion handler在类  `SearchVC+SearchBarDelegate.swift`.
7. 所有tasks默认是被挂起; 调用方法 `resume()` 开始data task.

翻到类 `SearchVC+SearchBarDelegate.swift`  的方法 `searchBarSearchButtonClicked(_ searchBar: UISearchBar) ` 会执行查询成功后，关闭转菊花(表示请求结束), 存储结果到searchResults, 接着更新 table view. 
运行程序，输入搜索字符串，搜索结果列表图如下：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190214151828650.png)
>注释: 默认的HTTP请求方法是GET. 如果要data task请求POST, PUT 或者 DELETE, 创建URLRequest，参数设置属性url,  HTTPMethod, 创建data task 请求参数为URLRequest, 而不是URL.

# Download Task
查询到歌曲列表，下一步是点击下载歌曲，并保存歌曲到沙盒。
## Download Class
为了方便处理多次下载，创建一个对象记录下载的状态。
> 在**Mode Group**创建一个Swift文件，命名为 `Download.swift` 
```swift
class Download {
  var track: Track
  init(track: Track) {
    self.track = track
  }
  
  // Download service sets these values:
  var task: URLSessionDownloadTask?
  var isDownloading = false
  var resumeData: Data?
  
  // Download delegate sets this value:
  var progress: Float = 0
  
}

```
代码解析：
1. track: 歌曲的详细信息.
2. task: URLSessionDownloadTask，下载track的task.
3. isDownloading: 下载是在进行还是暂停.
4. resumeData: 保存下载过程中的Data，当用户暂停下载task的时候. 如果主机服务器支持恢复下载，就可以恢复断点续传.
5. progress: 下载进度，小数范围0.0~1.0.

接下来，在类 `Networking/DownloadService.swift` , 在类的最上面增加属性:
```swift
var activeDownloads: [URL: Download] = [:]

```
这个字典的key为url，value为active Download.
# URLSessionDownloadDelegate
处理response数据有两种方式，一是block形式创建completion handler, 上面创建data task就是这样. 但是如果要更新下载进度，就要用到第二种代理方式，实现delegate.

有好几种session delegate protocols, 请参看[官方文档URLSession](https://developer.apple.com/reference/foundation/urlsession) . URLSessionDownloadDelegate负责处理针对下载任务(download tasks)的task-level事件.

一会要在类 SearchViewController 设置session delegate, 首先创建extension实现session delegate protocol.

在Controller group 创建Swift文件 SearchVC+URLSessionDelegates.swift:
```swift
extension SearchViewController: URLSessionDownloadDelegate {
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, 
    didFinishDownloadingTo location: URL) { 
    print("Finished downloading to \(location).")
  }
}

```
当下载完成，会调用上面的回调。

# 创建Download Task
创建专用的session处理下载任务download tasks.
在类 Controller/SearchViewController.swift, 方法viewDidLoad()之前增加下面属性:
```swift
lazy var downloadsSession: URLSession = {
  let configuration = URLSessionConfiguration.default
  return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
}()

```
上面初始化了session，设置了default configuration, 指定delegate, 使可以接受URLSession events，监听下载进度.

设置delegate queue为nil，相对于创建了串行队列，去调用代理方法delegate methods和block回调completion handlers.

懒加载创建downloadsSession: 这样等view controller初始化完毕, 再把self设置为delegate的参数.

在方法 viewDidLoad()里的最后一行增加:
```swift
downloadService.downloadsSession = downloadsSession

```
设置DownloadService的属性downloadsSession.

delegate已经设置好，创建download task去下载音乐🎵.

当用户点击歌曲的下载按钮, SearchViewController, 触发 TrackCellDelegate, 调用 `startDownload(_:)` 。在类 Networking/DownloadService.swift, 替换方法 `startDownload(_:)` 的实现:

```swift
func startDownload(_ track: Track) {
  // 1
  let download = Download(track: track)
  // 2
  download.task = downloadsSession.downloadTask(with: track.previewURL)
  // 3
  download.task!.resume()
  // 4
  download.isDownloading = true
  // 5
  activeDownloads[download.track.previewURL] = download
}

```
 代码解析:

1. 初始化Download对象.
2. 用传递过来的session, 创建URLSessionDownloadTask，设置参数URL, 设置Download的task属性值为URLSessionDownloadTask.
3. 调用resume() 开始下载任务.
4. 表明下载进度开始.
5. 最后设置字典activeDownloads, key为URL，value为download对象.

运行app > 搜索歌曲 > 点击下载 > 等待下载完成，控制台会打印下载的临时文件路径。

# 保存并播放歌曲
当下载结束调用回调 `urlSession(_:downloadTask:didFinishDownloadingTo:)` ，提供了保存歌曲到临时路径. 接下来需要把歌曲保存到沙盒永久位置.

在类 `SearchVC+URLSessionDelegates`, 替换方法`urlSession(_:downloadTask:didFinishDownloadingTo:)` 的打印内容为:
```swift
// 1
guard let sourceURL = downloadTask.originalRequest?.url else { return }
let download = downloadService.activeDownloads[sourceURL]
downloadService.activeDownloads[sourceURL] = nil
// 2
let destinationURL = localFilePath(for: sourceURL)
print(destinationURL)
// 3
let fileManager = FileManager.default
try? fileManager.removeItem(at: destinationURL)
do {
  try fileManager.copyItem(at: location, to: destinationURL)
  download?.track.downloaded = true
} catch let error {
  print("Could not copy file to disk: \(error.localizedDescription)")
}
// 4
if let index = download?.track.index {
  DispatchQueue.main.async {
    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
  }
}

```
代码解析：
1. 从task中解析出request URL, 把正在下载任务字典activeDownloads，剔除掉该完成的任务.
2. 把临时路径保存的歌曲文件，通过类SearchViewController.swift的辅助方法 `localFilePath(for:)` 创建到沙盒的Documents永久路径.
3. 用 FileManager, 把歌曲从临时路径copy到Document的永久路径. 设置downloaded属性为true.
4. 最后，刷新tableView UI隐藏下载按钮.

运行project > 搜索歌曲 > 点击下载 > 当下载完成 > 控制台打印歌曲路径:
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190215104629114.png)
当下载按钮隐藏后，已经下载属性downloaded为true. 点击该歌曲，可以听到歌曲，有AVPlayerViewController播放界面:
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190215104815371.png)
# 暂停, 恢复 和 取消 下载
这节实现下载过程中的控制：暂停，恢复，取消操作。

从取消下载开始。在类 `DownloadService.swift` ,  替换方法 `cancelDownload(_:)` 里面的内容如下:
```swift
func cancelDownload(_ track: Track) {
  if let download = activeDownloads[track.previewURL] {
    download.task?.cancel()
    activeDownloads[track.previewURL] = nil
  }
}

```
代码解析：
获取点击的正在下载download对象，取消下载任务。把该下载对象，从下载中的字典中移除。

接下来实现暂停下载，替换方法 `pauseDownload(_:)` 为如下：
```swift
func pauseDownload(_ track: Track) {
  guard let download = activeDownloads[track.previewURL] else { return }
  if download.isDownloading {
    download.task?.cancel(byProducingResumeData: { data in
      download.resumeData = data
    })
    download.isDownloading = false
  }
}

```
代码解析：
暂停跟取消的区别是保存了已经下载的数据信息，以备恢复操作。并把正在下载的状态改为false。

接下来是恢复下载，替换方法 `resumeDownload(_:)` 内容：
```swift
func resumeDownload(_ track: Track) {
  guard let download = activeDownloads[track.previewURL] else { return }
  if let resumeData = download.resumeData {
    download.task = downloadsSession.downloadTask(withResumeData: resumeData)
  } else {
    download.task = downloadsSession.downloadTask(with: download.track.previewURL)
  }
  download.task!.resume()
  download.isDownloading = true
}

```
代码解析：
当用户恢复下载，检查是否有暂停下载保留的数据，如果有就继续之前的下载 `downloadTask(withResumeData:)` . 如果没有之前的数据, 则创建 download task下载 URL.

所有操作默认都是挂起的，调用 `resume()` 开始下载。更新状态 isDownloading 为 true, 表示正在下载.

下载控制逻辑已经实现完毕，接下来需要UI事件的响应。

在类 `TrackCell.swift`, 把方法名 `configure(track:downloaded:)` 修改为 `configure(track:downloaded:download:)` :
```swift
func configure(track: Track, downloaded: Bool, download: Download?) {

```
在类 `SearchViewController.swift`, 修复调用方法 `tableView(_:cellForRowAt:)`:
```swift
cell.configure(track: track, downloaded: track.downloaded, 
  download: downloadService.activeDownloads[track.previewURL])

```
代码解析：
从正在下载字典activeDownloads提取download对象，传递给cell.

在类 `TrackCell.swift`, 在方法 `configure(track:downloaded:download:)` 定位到两个 TODOs. 替换第一个 // TODO 为以下变量:
```swift
var showDownloadControls = false

```

替换第二个 // TODO 为:
```swift
if let download = download {
  showDownloadControls = true
  let title = download.isDownloading ? "Pause" : "Resume"
  pauseButton.setTitle(title, for: .normal)
}

```
代码解析：

非空的下载对象download表示正在下载, cell显示下载控制: 暂停/恢复，取消. 暂停和恢复不能同时存在，公用同一个按钮，点击同一个按钮切换状态.

在if条件结构体的下面，增加按钮显示隐藏控制:
```swift
pauseButton.isHidden = !showDownloadControls
cancelButton.isHidden = !showDownloadControls

```
代码解析：
下载控制按钮，只有在正在下载才会显示.

最后，替换该方法的最后一行代码:
```swift
downloadButton.isHidden = downloaded

```
为如下代码
```swift
downloadButton.isHidden = downloaded || showDownloadControls

```
运行项目，控制下载状态，如图：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190216114836122.png)

# 显示下载进度
提高用户体验，显示下载进度条。有个session delegate很好地更新进度。
首先，在类 `TrackCell.swift` , 增加辅助方法:
```swift
func updateDisplay(progress: Float, totalSize : String) {
  progressView.progress = progress
  progressLabel.text = String(format: "%.1f%% of %@", progress * 100, totalSize)
}

```
cell有 progressView显示进度条 和 progressLabel 显示下载数据. 回调方法将会调用辅助方法更新UI数据.

接着，在类 `SearchVC+URLSessionDelegates.swift` 的 URLSessionDownloadDelegate extension, 增加代理方法delegate method:
```swift
func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, 
  didWriteData bytesWritten: Int64, totalBytesWritten: Int64, 
  totalBytesExpectedToWrite: Int64) {
  // 1
  guard let url = downloadTask.originalRequest?.url,
    let download = downloadService.activeDownloads[url]  else { return }
  // 2
  download.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
  // 3
  let totalSize = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
  // 4
    DispatchQueue.main.async {
    if let trackCell = self.tableView.cellForRow(at: IndexPath(row: download.track.index,
      section: 0)) as? TrackCell {
      trackCell.updateDisplay(progress: download.progress, totalSize: totalSize)
    }
  }
}

```
代码解析：
1. 从downloadTask 解析出URL , 在下载中字典active downloads的key为URL， 获取Download对象 .
2. 代理方法提供了已经下载的bytes和预期文件总大小bytes，借此可以计算已经下载的比例进度.
3. ByteCountFormatter通过byte计算出人类可读的大小数据.
4. 最后，在主队列更新UI的进度，和文件大小数据.

现在，更新cell的配置，正确的显示下载进度和状态. 在类 `TrackCell.swift` 的方法 `configure(track:downloaded:download:)` , 在if判读条件里面，在pause button设置title的后面增加:
```swift
progressLabel.text = download.isDownloading ? "Downloading..." : "Paused"

```
代码解析：
progressLabel在未下载这前，和暂停的时候显示内容.

在if条件结构体下面，增加下面代码:
```swift
progressView.isHidden = !showDownloadControls
progressLabel.isHidden = !showDownloadControls

```
代码解析：
下载进度条，和文件大小，只有在下载中才显示.

运行project; 下载歌曲，将会看到下载的进度UI:
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190216155716922.png)
# Background下载任务
在Background下载任务，即使app运行在backgrouded，甚至crashed，下载任务任然继续。这在下载大文件的时候，是相当必要的功能.

app没有在运行，下载任务继续是怎么办到的呢？操作系统OS运行一个独立与app的守护进程去管理background transfer tasks, 并且会在合适时机调用相应的代理方法通知app. 即使app进程已经结束，也不影响background的任务.

当任务完成，守护进程会重新启动app在background. 重启的app会重新创建background session, 去接收相关代理信息, 并执行相关动作，比如持久化下载文件到硬盘.
>注意: 如果是用户主动杀掉app进程，系统将会取消该app的所有session’s background transfers, 并且不会重启app.

实现上面的魔术，通过创建带有background session configuration的session.
在类 `SearchViewController.swift`, 在初始化downloadsSession, 找到下面的代码:
```swift
let configuration = URLSessionConfiguration.default

```
把上面的代码，修改为：
```swift
let configuration = URLSessionConfiguration.background(withIdentifier: 
  "bgSessionConfiguration")

```
替代default session configuration, 更改为 background session configuration. 为session设置唯一标识unique identifier，从而创建新的background session.
>注意: 必须不能创建多于1个background session, 因为系统用该唯一标识identifier去关联任务task和会话session.

如果background task 完成，然而app没有在运行, app将会被重启在background. 所以需要接受唤起的代理事件delegate.

在类 `AppDelegate.swift` 的最上面, 增加block属性:
```swift
var backgroundSessionCompletionHandler: (() -> Void)?

```

接着，增加代理方法:
```swift
func application(_ application: UIApplication, handleEventsForBackgroundURLSession 
  identifier: String, completionHandler: @escaping () -> Void) {
  backgroundSessionCompletionHandler = completionHandler
}

```
代码解析：
保存completionHandler到变量，一会调用.

`application(_:handleEventsForBackgroundURLSession:)` 唤醒app去处理完成下载后的后续任务. 需要在该方法处理两件事:

1. app需要用delegate方法提供唯一标识，重新创建background configuration和session. 幸运的是，app启动后的rootViewController为SearchViewController，viewDidLoad已经创建好该background session!
2. 需要捕获delegate提供completion handler. 唤醒completion handler 告诉你，系统已经下载完毕，app需要处理把下载文件保存到本地，更新UI，即使在app switcher切换状态，用户也可以看到完成的样子.

完成下载后，唤醒的代理方法为 `urlSessionDidFinishEvents(forBackgroundURLSession:)` : 是URLSessionDelegate 方法，当background session完成时，该方法URLSessionDelegate会被触发.

在类 `SearchVC+URLSessionDelegates.swift` 找到头文件引入 import:
```swift
import Foundation

```
在上面引入的下面，增加新的引入：

```swift
import UIKit

```

最后，增加下面的扩展extension:
```swift
extension SearchViewController: URLSessionDelegate {

  // Standard background session handler
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
        let completionHandler = appDelegate.backgroundSessionCompletionHandler {
        appDelegate.backgroundSessionCompletionHandler = nil
        completionHandler()
      }
    }
  }

}

```
代码解析：
获取到app delegate已经保存的completion handler，并在主线程唤醒. 通过UIApplication 的shared delegate 引用 app delegate，所以需要引入UIKit.

运行app; 点击几首歌下载(concurrent downloads), 点击Home键使app在background运行. 等待一会，你觉得已经下载完毕，则双击Home键，在app switcher中看下载状态，已经下载完成得以验证background session已经实现.
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190216164637928.png)
Apple music App已经完成。

# 总结
恭喜你，完成了URLSession的请求、下载，已经下载状态的控制。
代码下载：
https://github.com/zgpeace/URLSessionTutorial
# 参考
https://www.raywenderlich.com/567-urlsession-tutorial-getting-started
https://developer.apple.com/documentation/foundation/urlsessionconfiguration
https://developer.apple.com/documentation/foundation/urlsession
