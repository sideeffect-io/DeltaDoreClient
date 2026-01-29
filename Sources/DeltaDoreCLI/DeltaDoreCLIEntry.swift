import Foundation
import DeltaDoreClient

@main
struct DeltaDoreCLI {
    static func main() async {
        let stdout = ConsoleWriter(handle: .standardOutput)
        let stderr = ConsoleWriter(handle: .standardError)

        let action = parseArguments(Array(CommandLine.arguments.dropFirst()))
        switch action {
        case .help(let text):
            await stdout.writeLine(text)
            return
        case .failure(let message):
            await stderr.writeLine(message)
            await stdout.writeLine(helpText())
            return
        case .run(let options):
            await runCLI(options: options, stdout: stdout, stderr: stderr)
        case .runAuto(let options):
            guard let resolved = await resolveAutoConfiguration(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(options: resolved, stdout: stdout, stderr: stderr)
        case .runResolved(let options):
            guard let resolved = await resolveExplicitConfiguration(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(options: resolved, stdout: stdout, stderr: stderr)
        }
    }
}
