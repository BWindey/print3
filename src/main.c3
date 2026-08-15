module print3;
import std::io;

fn int main(String[] args) {
	if (args.len < 2) {
		io::eprintn("Expected one ore more arguments but got none.");
		return 10;
	}
	Print3Config config = parse_cli_args(args[1..]);

	setup_print_file(mem, config);
	defer cleanup_print_file(config);

	foreach (i, filename : config.files) {
		if (config.files.len() > 1) {
			if (i > 0) internal_print_char('\n');
			internal_print(Ansi.UNDERLINE);
			internal_print(filename);
			internal_print(Ansi.RESET);
			internal_print_char('\n');
		}
		print_file(config, filename)!!;
	}
	return 0;
}
