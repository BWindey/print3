module print3;
import std::io;
import std::encoding::experimental::regex;
import std::math;


macro bool is_escaped_char(String line, sz idx) {
	if (idx == 0) return false;

	idx--;
	sz backslash_counter = 0;

	while (idx > 0 && line[idx] == '\\') {
		idx--;
		backslash_counter++;
	}

	return backslash_counter % 2 != 0;
}

Regex number_regex @local @noinit;
String tab_replacement @local @noinit;
Allocator used_allocator @local @noinit;
sz nr_format_len @local @noinit;
bool local_vars_started @local = false;

fn sz String.visual_len(self) {
	sz len = 0;
	for (sz i = 0; i < self.len;) {
		char c = self[i];
		switch (c) {
			// Visible ASCII
			case 32..126:
				len += 1;
				i += 1;

			// UTF-8 multibyte
			case 0b1100_0000..0b1101_1111:
				len += 1;
				i += 2;
			case 0b1110_0000..0b1110_1111:
				len += 1;
				i += 3;
			case 0b1111_0000..0b1111_0111:
				len += 1;
				i += 4;

			case 0..31:
			case 127:
				i += 1;

			default:
				// Should not happen but I don't really want it to crash...
				i += 1;
		}
	}

	return len;
}

fn void print_number(Print3Config config, String line, sz* i) {
	Match m = number_regex.first_match(line[*i..])!!;
	sz number_end_idx = *i + m.end;
	io::print(config.theme.number);
	io::print(line[*i:m.end]);
	io::print(Ansi.RESET);
	*i += m.end;
}

// TODO: use symbol colour for escape sequences in strings
// TODO: support doc contracts
// TODO: for lines that do not get printed, add a scan for opening/closing
//       contracts, strings, comments, ...

sz comment_depth = 0;
bool in_raw_string = false;

fn void print_line(Print3Config config, String line, sz i) @local => @pool() {
	sz chars_printed = 0;
	File* stdout = io::stdout();
	if (config.add_line_nr) io::printf(config.nr_format, i)!!;

	line = line.treplace("\t", tab_replacement);

	sz idx = 0;

	// Handle multiline comments / comment blocks
	if (comment_depth > 0) stdout.write(config.theme.comment)!!;
	sz start_comment = idx;
	while (comment_depth > 0 && idx < line.len) {
		if (idx + 1 < line.len && line[idx:2] == "/*") {
			comment_depth += 1;
			idx += 2;
		} else if (idx + 1 < line.len && line[idx:2] == "*/") {
			comment_depth -= 1;
			idx += 2;
		} else {
			idx++;
		}
	}
	if (idx > start_comment) {
		stdout.write(line[start_comment..idx - 1])!!;
		if (comment_depth <= 0) stdout.write(Ansi.RESET)!!;
	}
	if (idx >= line.len) stdout.write(Ansi.RESET)!!;

	// Handle multiline raw strings
	if (in_raw_string) stdout.write(config.theme.string)!!;
	while (in_raw_string && idx < line.len) {
		if (line[idx] == '`') {
			in_raw_string = false;
			stdout.write_byte('`')!!;
			stdout.write(Ansi.RESET)!!;
		} else {
			stdout.write_byte(line[idx])!!;
		}
		idx++;
	}
	if (idx >= line.len) stdout.write(Ansi.RESET)!!;

	// Handle rest
	while (idx < line.len) {
		switch (line[idx]) {
			case ' ':
				stdout.write_byte(' ')!!;
				idx++;

			case '/':
				if (idx + 1 < line.len) {
					sz end_of_comment;
					if (line[idx + 1] == '/') {
						end_of_comment = line.len - 1;
					} else if (line[idx + 1] == '*') {
						end_of_comment = idx + 3;
						while (
							end_of_comment < line.len
							&& line[end_of_comment - 1:2] != "*/"
						) {
							end_of_comment++;
						}
						if (end_of_comment >= line.len) {
							end_of_comment = line.len - 1;
							comment_depth += 1;
						}
					} else {
						nextcase;
					}
					stdout.write(config.theme.comment)!!;
					stdout.write(line[idx..end_of_comment])!!;
					stdout.write(Ansi.RESET)!!;
					idx = end_of_comment + 1;
				} else {
					nextcase;
				}

			case '.':
			case ',':
			case '(': case ')':
			case '[': case ']':
			case '{': case '}':
			case '<': case '>':
			case '+': case '-':
			case '*':
			case '%':
			case '^':
			case ':':
			case ';':
			case '=':
			case '?':
			case '!':
			case '|':
			case '&':
			case '~':
				stdout.write(config.theme.symbol)!!;
				stdout.write_byte(line[idx])!!;
				stdout.write(Ansi.RESET)!!;
				idx++;

			case '\'':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '\'' || is_escaped_char(line, idx))
				) { idx++; }
				stdout.write(config.theme.string)!!;
				stdout.write(line[word_start_idx..idx])!!;
				stdout.write(Ansi.RESET)!!;
				idx++;

			case '"':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '"' || is_escaped_char(line, idx))
				) { idx++; }
				stdout.write(config.theme.string)!!;
				stdout.write(line[word_start_idx..idx])!!;
				stdout.write(Ansi.RESET)!!;
				idx++;
			case '`':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '`' || is_escaped_char(line, idx))
				) { idx++; }
				if (idx == line.len) {
					idx--;
					in_raw_string = true;
				}
				stdout.write(config.theme.string)!!;
				stdout.write(line[word_start_idx..idx])!!;
				stdout.write(Ansi.RESET)!!;
				idx++;

			case '0'..'9':
				print_number(config, line, &idx);

			case 'A'..'Z':
				sz word_start_idx = idx;
				bool is_al_caps = true;
				idx++;

				while (
					idx < line.len &&
					(ascii::@is_alnum(line[idx]) || line[idx] == '_')
				) {
					if (ascii::@is_lower(line[idx])) is_al_caps = false;
					idx++;
				}
				sz word_end_idx = idx - 1;
				String word = line[word_start_idx..word_end_idx];

				if (is_al_caps) {
					stdout.write(config.theme.constant)!!;
					stdout.write(word)!!;
					stdout.write(Ansi.RESET)!!;
				} else {
					stdout.write(config.theme.type)!!;
					stdout.write(word)!!;
					stdout.write(Ansi.RESET)!!;
				}

			case '@':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len &&
					(ascii::@is_alnum(line[idx]) || line[idx] == '_')
				) {
					idx++;
				}
				sz word_end_idx = idx - 1;
				if (idx < line.len && line[idx] == '(') {
					stdout.write(Ansi.BOLD)!!;
				}
				stdout.write(config.theme.at)!!;
				stdout.write(line[word_start_idx..word_end_idx])!!;
				stdout.write(Ansi.RESET)!!;

			default:
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len &&
					(ascii::@is_alnum(line[idx]) || line[idx] == '_')
				) {
					idx++;
				}
				sz word_end_idx = idx - 1;
				String word = line[word_start_idx..word_end_idx];

				switch (word) {
					case "fn":
					case "macro":
					case "return":
					case "module":
					case "import":
					case "switch":
					case "case":
					case "default":
					case "nextcase":
					case "if":
					case "else":
					case "while":
					case "do":
					case "for":
					case "foreach":
					case "foreach_r":
					case "try":
					case "catch":
					case "true":
					case "false":
					case "enum":
					case "struct":
					case "union":
					case "assert":
					case "faultdef":
					case "attrdef":
					case "typedef":
					case "const":
					case "static":
					case "alias":
					case "var":
					case "$for":
					case "$endfor":
					case "$endforeach":
					case "$endif":
					case "$endswitch":
					case "$if":
					case "$else":
					case "$switch":
					case "$case":
					case "$default":
					case "$echo":
					case "$error":
					case "$eval":
					case "$evaltype":
					case "$exec":
					case "$extnameof":
						stdout.write(config.theme.keyword)!!;
						stdout.write(word)!!;
						stdout.write(Ansi.RESET)!!;
					case "float":
					case "double":
					case "bool":
					case "int":
					case "uint":
					case "long":
					case "ulong":
					case "char":
					case "ichar":
					case "short":
					case "ushort":
					case "sz":
					case "usz":
					case "void":
						stdout.write(config.theme.type)!!;
						stdout.write(word)!!;
						stdout.write(Ansi.RESET)!!;
					default:
						if (line[word_start_idx] == '$') {
							stdout.write(config.theme.comptime_ident)!!;
							stdout.write(word)!!;
							stdout.write(Ansi.RESET)!!;
						} else if (idx < line.len && line[idx] == '(') {
							stdout.write(Ansi.BOLD)!!;
							stdout.write(config.theme.call)!!;
							stdout.write(word)!!;
							stdout.write(Ansi.RESET)!!;
						} else if (
							word_start_idx - 1 >= 0
							&& line[word_start_idx - 1] == '.'
							&& (
								word_start_idx - 2 < 0
								|| line[word_start_idx - 2].is_alnum()
								|| line[word_start_idx - 2].is_blank()
								|| line[word_start_idx - 2] == '_'
								|| line[word_start_idx - 2] == '{'
								|| line[word_start_idx - 2] == ']'
							)
						) {
							stdout.write(config.theme.member)!!;
							stdout.write(word)!!;
							stdout.write(Ansi.RESET)!!;
						} else {
							stdout.write(word)!!;
						}
				}
		}
	}

	if (line.len == 0 || line[^1] != '\n') stdout.write_byte('\n')!!;
}

fn void setup_print_file(Allocator allocator, Print3Config config) {
	if (local_vars_started) return;

	number_regex = regex::compile(
		allocator,
		`^[-+]?(`
		`0x[0-9a-f](_?[0-9a-f])*(\.[0-9a-f](_?[0-9a-f])*p[+-]?[0-9](_?[0-9])*[fd]?|u?l{0,2})|`
		`(0b[01](_?[01])*|0o[0-7](_?[0-7])*)(u?l{0,2})|`
		`[0-9](_?[0-9])*(\.[0-9](_?[0-9])*(e[+-]?[0-9](_?[0-9])*)?[fd]?|e[+-]?[0-9](_?[0-9])*[fd]?|u?l{0,2})`
		`)`,
		EXTENDED | ICASE
	)!!;

	tab_replacement = (String) alloc::new_array(
		allocator, char, config.spaces_per_tab
	);
	mem::set(&tab_replacement[0], ' ', config.spaces_per_tab);

	if (config.add_line_nr) {
		nr_format_len = config.nr_format.visual_len();
	} else {
		nr_format_len = 0;
	}

	used_allocator = allocator;

	local_vars_started = true;
}

fn void cleanup_print_file() {
	number_regex.free();
	alloc::free(used_allocator, tab_replacement.ptr);
}


fn void? print_file(Print3Config config, String file_name) => @pool() {
	File open_file = file::open(file_name, "r")!;
	defer open_file.close();

	comment_depth = 0;
	in_raw_string = false;

	sz i = 0;
	while (try line = io::treadline(&open_file)) {
		i++;
		if (config.line_start >= 0 && i < config.line_start) continue;
		if (config.line_stop >= 0 && i > config.line_stop) continue;

		// TODO:
		// - truncate too long lines (80)
		print_line(config, line, i);
	}
}
