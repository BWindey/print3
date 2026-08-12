module hello;
import std::collections::list;

struct Foo {
	int x;
	char* pointy;
}

/*
	Main function, /* with a nested comment
	whaaaat? */
*/
fn void main() {
	Foo f = {
		.x = 324,
		.pointy = null,
	};
	double x = 12.3e11;
	double y = -1.3e-3;
	int x = 0xfEE;
}
