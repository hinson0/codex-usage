import Testing

@main
struct CodexUsageTestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
