// The build stamp, so the engine can say which build is answering.
//
// Shared with both UIs through a symlink; see the file itself. The engine has
// no cxx-qt build to do, so this is the whole of its build script.
include!("build_date.rs");

fn main() {
    emit_build_date();
}
