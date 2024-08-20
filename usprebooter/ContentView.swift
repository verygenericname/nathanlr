import SwiftUI

struct ContentView: View {
    @State var staticHeadroomMB = getPhysicalMemorySize() / 1048576;
    @State var pUaFPages = 3072.0;
    var body: some View {
        VStack {
            HStack {
                Button("\"jailbreak\"") {
                    DispatchQueue.main.async {
                        do_kopen(UInt64(pUaFPages), 2, 1, 1, Int(staticHeadroomMB), true);
                        go()
                        do_kclose()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Code to be executed after a delay of 0.5 seconds
                            userspaceReboot()
                        }
                    }
                }
            }
        }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Color(.black)
                        .opacity(0.0)
                }
        }
}
