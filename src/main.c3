module print3;
import std::io;

fn int main(String[] args) {
	if (args.len < 2) {
		io::eprintn("Expected one ore more arguments but got none.");
		return 10;
	}
	Print3Config config = parse_cli_args(args[1..]);

	foreach (i, filename : config.files) {
		if (config.files.len() > 2) {
			if (i > 0) io::print("\n");
			io::printfn("%s%s%s:", Ansi.UNDERLINE, filename, Ansi.RESET);
		}
		print_file(config, filename)!!;
	}
	return 0;
}
