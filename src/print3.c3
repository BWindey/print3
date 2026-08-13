module print3;
import std::io;
import std::encoding::experimental::regex;
import std::math;
import bufferedoutput;

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
BufferedOutput buffered_output @local @noinit;
BackedArenaAllocator* internal_allocator @local @noinit;
// sz nr_format_len @local @noinit;

bool local_vars_started @local = false;

// fn sz String.visual_len(self) {
// 	sz len = 0;
// 	for (sz i = 0; i < self.len;) {
// 		char c = self[i];
// 		switch (c) {
// 			// Visible ASCII
// 			case 32..126:
// 				len += 1;
// 				i += 1;
//
// 			// UTF-8 multibyte
// 			case 0b1100_0000..0b1101_1111:
// 				len += 1;
// 				i += 2;
// 			case 0b1110_0000..0b1110_1111:
// 				len += 1;
// 				i += 3;
// 			case 0b1111_0000..0b1111_0111:
// 				len += 1;
// 				i += 4;
//
// 			case 0..31:
// 			case 127:
// 				i += 1;
//
// 			default:
// 				// Should not happen but I don't really want it to crash...
// 				i += 1;
// 		}
// 	}
//
// 	return len;
// }


<*
	Custom line nr printer as replacement for printf().

	@require line >= 0
*>
fn void print_line_nr(Print3LineNr nr_format, sz line) {
	// for buffer size: usz::max = 4294967296 => 10 digits
	// sz cannot be negative, so no 11th char needed
	static char[10] nr_buffer;

	buffered_output.write(nr_format.pre);
	sz buffer_idx = 0;
	while (line > 0) {
		nr_buffer[9 - buffer_idx] = (char) (line % 10) + '0';
		line /= 10;
		buffer_idx += 1;
	}
	// buffer_idx == len of line-nr in printed chars

	if (nr_format.left_align) {
		buffered_output.write(nr_buffer[buffer_idx..]);
	}
	// padding
	for (int i = 0; i < nr_format.min_size - buffer_idx; i++) {
		buffered_output.write_byte(nr_format.padding_char);
	}
	if (!nr_format.left_align) {
		buffered_output.write(nr_buffer[buffer_idx..]);
	}

	buffered_output.write(nr_format.post);
}

fn void print_number(Print3Config config, String line, sz* i) {
	Match m = number_regex.first_match(line[*i..])!!;
	sz number_end_idx = *i + m.end;
	buffered_output.write(config.theme.number);
	buffered_output.write(line[*i:m.end]);
	buffered_output.write(Ansi.RESET);
	*i += m.end;
}

// TODO: use symbol colour for escape sequences in strings
// TODO: support doc contracts
// TODO: for lines that do not get printed, add a scan for opening/closing
//       contracts, strings, comments, ...

sz comment_depth = 0;
bool in_raw_string = false;

fn void print_line(Print3Config config, String line, sz i) @local {
	sz chars_printed = 0;
	if (config.add_line_nr) {
		print_line_nr(config.nr_format, i);
	}

	line = line.replace(internal_allocator, "\t", tab_replacement);

	sz idx = 0;

	// Handle multiline comments / comment blocks
	if (comment_depth > 0) buffered_output.write(config.theme.comment)!!;
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
		buffered_output.write(line[start_comment..idx - 1])!!;
		if (comment_depth <= 0) buffered_output.write(Ansi.RESET)!!;
	}
	if (idx >= line.len) buffered_output.write(Ansi.RESET)!!;

	// Handle multiline raw strings
	if (in_raw_string) buffered_output.write(config.theme.string)!!;
	while (in_raw_string && idx < line.len) {
		if (line[idx] == '`') {
			in_raw_string = false;
			buffered_output.write_byte('`')!!;
			buffered_output.write(Ansi.RESET)!!;
		} else {
			buffered_output.write_byte(line[idx])!!;
		}
		idx++;
	}
	if (idx >= line.len) buffered_output.write(Ansi.RESET)!!;

	// Handle rest
	while (idx < line.len) {
		switch (line[idx]) {
			case ' ':
				buffered_output.write_byte(' ')!!;
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
					buffered_output.write(config.theme.comment)!!;
					buffered_output.write(line[idx..end_of_comment])!!;
					buffered_output.write(Ansi.RESET)!!;
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
				buffered_output.write(config.theme.symbol)!!;
				buffered_output.write_byte(line[idx])!!;
				buffered_output.write(Ansi.RESET)!!;
				idx++;

			case '\'':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '\'' || is_escaped_char(line, idx))
				) { idx++; }
				buffered_output.write(config.theme.string)!!;
				buffered_output.write(line[word_start_idx..idx])!!;
				buffered_output.write(Ansi.RESET)!!;
				idx++;

			case '"':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '"' || is_escaped_char(line, idx))
				) { idx++; }
				buffered_output.write(config.theme.string)!!;
				buffered_output.write(line[word_start_idx..idx])!!;
				buffered_output.write(Ansi.RESET)!!;
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
				buffered_output.write(config.theme.string)!!;
				buffered_output.write(line[word_start_idx..idx])!!;
				buffered_output.write(Ansi.RESET)!!;
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
					buffered_output.write(config.theme.constant)!!;
					buffered_output.write(word)!!;
					buffered_output.write(Ansi.RESET)!!;
				} else {
					buffered_output.write(config.theme.type)!!;
					buffered_output.write(word)!!;
					buffered_output.write(Ansi.RESET)!!;
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
					buffered_output.write(Ansi.BOLD)!!;
				}
				buffered_output.write(config.theme.at)!!;
				buffered_output.write(line[word_start_idx..word_end_idx])!!;
				buffered_output.write(Ansi.RESET)!!;

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
					case "alias":
					case "assert":
					case "asm":
					case "attrdef":
					case "attrgroup":
					case "attrmacro":
					case "bitstruct":
					case "break":
					case "case":
					case "catch":
					case "constdef":
					case "const":
					case "constset":
					case "cenum":
					case "continue":
					case "default":
					case "defer":
					case "do":
					case "else":
					case "enum":
					case "extern":
					case "false":
					case "excuse":
					case "faultdef":
					case "faultset":
					case "faultconst":
					case "for":
					case "foreach":
					case "foreach_r":
					case "fn":
					case "tlocal":
					case "if":
					case "inline":
					case "import":
					case "lengthof":
					case "macro":
					case "module":
					case "nextcase":
					case "null":
					case "interface":
					case "return":
					case "static":
					case "struct":
					case "switch":
					case "true":
					case "try":
					case "typedef":
					case "distinct":
					case "union":
					case "var":
					case "while":
					case "$assert":
					case "$case":
					case "$default":
					case "$defined":
					case "$echo":
					case "$else":
					case "$embed":
					case "$endfor":
					case "$endforeach":
					case "$endif":
					case "$endswitch":
					case "$eval":
					case "$error":
					case "$exec":
					case "$expand":
					case "$feat":
					case "$feature":
					case "$for":
					case "$foreach":
					case "$if":
					case "$include":
					case "$reflect":
					case "$stringify":
					case "$switch":
					case "$Typefrom":
					case "$Typeof":
					case "$vaarg":
						buffered_output.write(config.theme.keyword)!!;
						buffered_output.write(word)!!;
						buffered_output.write(Ansi.RESET)!!;
					case "void":
					case "bool":
					case "char":
					case "double":
					case "float":
					case "float16":
					case "bfloat":
					case "int128":
					case "ichar":
					case "int":
					case "iptr":
					case "sz":
					case "long":
					case "short":
					case "uint128":
					case "uint":
					case "ulong":
					case "uptr":
					case "ushort":
					case "usz":
					case "float128":
					case "any":
					case "fault":
					case "typeid":
					case "untypedlist":
						buffered_output.write(config.theme.type)!!;
						buffered_output.write(word)!!;
						buffered_output.write(Ansi.RESET)!!;
					default:
						if (line[word_start_idx] == '$') {
							buffered_output.write(config.theme.comptime_ident)!!;
							buffered_output.write(word)!!;
							buffered_output.write(Ansi.RESET)!!;
						} else if (idx < line.len && line[idx] == '(') {
							buffered_output.write(Ansi.BOLD)!!;
							buffered_output.write(config.theme.call)!!;
							buffered_output.write(word)!!;
							buffered_output.write(Ansi.RESET)!!;
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
							buffered_output.write(config.theme.member)!!;
							buffered_output.write(word)!!;
							buffered_output.write(Ansi.RESET)!!;
						} else {
							buffered_output.write(word)!!;
						}
				}
		}
	}

	sz foo = 0;
	if (line.len == 0 || line[^1] != '\n') buffered_output.write_byte('\n')!!;
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

	// if (config.add_line_nr) {
	// 	nr_format_len = config.nr_format.visual_len();
	// } else {
	// 	nr_format_len = 0;
	// }

	internal_allocator = allocators::new_backed_allocator(
		config.print_buffer_size + BufferedOutput::size + 2048u,
		allocator
	)!!;

	buffered_output = bufferedoutput::new(
		internal_allocator, config.print_buffer_size
	);

	tab_replacement = (String) alloc::new_array(
		internal_allocator, char, config.spaces_per_tab
	);
	mem::set(&tab_replacement[0], ' ', config.spaces_per_tab);

	local_vars_started = true;
}

fn void cleanup_print_file() {
	number_regex.free();
	buffered_output.flush()!!;
	internal_allocator.destroy();
}


fn void? print_file(Print3Config config, String file_name) {
	assert(local_vars_started == true);
	File open_file = file::open(file_name, "r")!;
	defer open_file.close();

	comment_depth = 0;
	in_raw_string = false;

	sz i = 0;
	sz line_alloc_mark = internal_allocator.mark();
	while (try line = io::readline(internal_allocator, &open_file)) {
		i++;
		if (config.line_start >= 0 && i < config.line_start) continue;
		if (config.line_stop >= 0 && i > config.line_stop) continue;

		// TODO:
		// - truncate too long lines (80)
		print_line(config, line, i);
		internal_allocator.reset(line_alloc_mark);
	}

	buffered_output.flush();
}
