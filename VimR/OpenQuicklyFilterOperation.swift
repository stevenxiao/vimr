/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Cocoa

class OpenQuicklyFilterOperation: NSOperation {

  private let chunkSize = 100
  private let maxResultCount = 500

  private unowned let openQuicklyWindow: OpenQuicklyWindowComponent
  private let pattern: String
  private let flatFileItems: [FileItem]
  private let cwd: NSURL

  init(forOpenQuicklyWindow openQuicklyWindow: OpenQuicklyWindowComponent) {
    self.openQuicklyWindow = openQuicklyWindow
    self.pattern = openQuicklyWindow.pattern
    self.cwd = openQuicklyWindow.cwd
    self.flatFileItems = openQuicklyWindow.flatFileItems
    
    super.init()
  }

  override func main() {
    self.openQuicklyWindow.scanCondition.lock()
    self.openQuicklyWindow.pauseScan = true
    defer {
      self.openQuicklyWindow.pauseScan = false
      self.openQuicklyWindow.scanCondition.broadcast()
      self.openQuicklyWindow.scanCondition.unlock()
    }

    if self.cancelled {
      return
    }

    let sorted: [ScoredFileItem]
    if pattern.characters.count == 0 {
      let truncatedItems = self.flatFileItems[0...min(self.maxResultCount, self.flatFileItems.count - 1)]
      sorted = truncatedItems.map { ScoredFileItem(score: 0, url: $0.url) }
    } else {
      DispatchUtils.gui { self.openQuicklyWindow.startProgress() }
      defer { DispatchUtils.gui { self.openQuicklyWindow.endProgress() } }

      let count = self.flatFileItems.count
      let chunksCount = Int(ceil(Float(count) / Float(self.chunkSize)))
      let useFullPath = pattern.containsString("/")
      let cwdPath = self.cwd.path! + "/"

      var result = [ScoredFileItem]()
      var spinLock = OS_SPINLOCK_INIT
      
      let cleanedPattern = useFullPath ? self.pattern.stringByReplacingOccurrencesOfString("/", withString: "")
                                       : self.pattern
      
      dispatch_apply(chunksCount, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) { [unowned self] idx in
        if self.cancelled {
          return
        }

        let startIndex = min(idx * self.chunkSize, count)
        let endIndex = min(startIndex + self.chunkSize, count)

        let chunkedItems = self.flatFileItems[startIndex..<endIndex]
        let chunkedResult: [ScoredFileItem] = chunkedItems.flatMap {
          if self.cancelled {
            return nil
          }

          let url = $0.url
          
          if useFullPath {
            let target = url.path!.stringByReplacingOccurrencesOfString(cwdPath, withString: "")
                                  .stringByReplacingOccurrencesOfString("/", withString: "")
            
            return ScoredFileItem(score: Scorer.score(target, pattern: cleanedPattern), url: url)
          }
          
          return ScoredFileItem(score: Scorer.score(url.lastPathComponent!, pattern: cleanedPattern), url: url)
        }

        if self.cancelled {
          return
        }

        OSSpinLockLock(&spinLock)
        result.appendContentsOf(chunkedResult)
        OSSpinLockUnlock(&spinLock)
      }

      if self.cancelled {
        return
      }

      sorted = result.sort(>)
    }

    if self.cancelled {
      return
    }

    DispatchUtils.gui {
      let result = Array(sorted[0...min(self.maxResultCount, sorted.count - 1)])
      self.openQuicklyWindow.reloadFileView(withScoredItems: result)
    }
  }
}