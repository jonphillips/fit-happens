import ChatAccessKit
import Darwin
import FitHappensMCPServer
import MCPServerKit

@main
enum FitHappensMCP {
  static func main() async {
    ChatAccessHelperProcess.enableDatalessMaterialization()
    await FitHappensMCPServer.make().run()
  }
}
