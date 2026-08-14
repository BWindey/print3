module bufferedinput;
import std::io;

<*
	A BufferedInput will provide a 'buffered_input.readline()' method that is
	as efficient as possible by reading 'buffered_input.size' bytes at a time
	into its internal buffer.

	When a line would be longer than 'buffered_input.size' and thus not fit
	into its internal buffer, it will use its backing allocator (same one
	as used to allocate the internal buffer) to create a string that the
	user of this struct will have to free.
	There is no warning that a line did not fit, so use this BufferedInput
	in combination with an allocator that you reset after each line, f.e.:
	```c3
	BufferedInput bi = bufferedinput::new(tmem, 1024, file::open("foo.txt")!!);
	while (true) {
		;@pool() {
			String? line = bi.readline();
			if (catch line) break;

			process_line(line);
		};
	}
	```
	(An alternative is using a `BackedArenaAllocator` with `.mark()` and
	 `.reset()`)
*>
struct BufferedInput {
	bool reached_eof;
	sz pos;
	sz end;
	File* input;
	Allocator backing_allocator;
	char[] buffer;
}

fn BufferedInput new(Allocator allocator, sz size, File* input) {
	BufferedInput bi;
	bi.buffer = alloc::new_array(allocator, char, size);
	bi.input = input;

	bi.end = 0;
	bi.pos = 0;

	bi.reached_eof = false;

	bi.backing_allocator = allocator;

	return bi;
}

<*
	Get a new line (bytes ended with a '\n').
	The ending '\n' will be stripped from the returned result, also if the '\n'
	is preceded by a '\r', it will also be stripped.
*>
fn String? BufferedInput.readline(&self) {
	if (self.reached_eof && self.pos == self.end) return io::EOF~;

	/*
		Conceptually think of the buffer as a sliding window.
		`pos` points to the beginning of unconsumed data,
		`end` points to the end of valid data.

		A newline either exists in this window or it does not. If it exists,
		simply return that slice and advance `pos` to a position behind the
		newline.
		If it does not exist, there are two cases
	 */

	// Scan for a newline
	sz newline = self.pos;
	while (newline < self.end && self.buffer[newline] != '\n') newline++;

	// Found a complete line in current buffer
	if (newline < self.end && self.buffer[newline] == '\n') {
		String line = (String) self.buffer[self.pos..newline - 1];
		if (line.len > 0 && line[^1] == '\r') line = line[..^1];

		self.pos = newline + 1;
		return line;
	}

	// EOF and no newline found at end
	if (self.reached_eof && newline == self.end) {
		if (newline <= self.pos) return io::EOF~;

		String line = (String) self.buffer[self.pos..self.end - 1];
		if (line.len > 0 && line[^1] == '\r') line = line[..^1];
		return line;
	}

	// No newline found and still space in buffer
	if (self.end - self.pos < self.buffer.len) {
		self.refill();
		return self.readline();
	}

	// Sanity check
	assert(self.pos == 0 && self.end == self.buffer.len);

	// Line too long
	DString dline = dstring::new_with_capacity(
		self.backing_allocator, self.buffer.len + self.buffer.len / 2
	);
	dline.append(self.buffer);
	self.pos = 0;
	self.end = 0;
	self.refill();

	// WARNING: this might waste quite a lot of memory, but we assume that
	// these long lines will almost never happen when you use a buffer of long
	// length, like 1024 or higher.
	if (try next_part = self.readline()) dline.append(next_part);
	return dline.str_view();
}

fn void BufferedInput.refill(&self) {
	if (self.pos > 0) {
		sz remaining = self.end - self.pos;

		mem::move(
			&self.buffer[0],
			self.buffer[self.pos..self.end - 1],
			remaining
		);

		self.pos = 0;
		self.end = remaining;
	}

	sz? read_bytes = self.input.read(self.buffer[self.end..]);

	if (catch read_bytes) {
		self.reached_eof = true;
	} else if (read_bytes == 0) {
		self.reached_eof = true;
	} else {
		self.end += read_bytes;
	}
}
