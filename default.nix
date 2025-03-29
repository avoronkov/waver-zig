let
  pkgs = import <nixpkgs> {};
in
pkgs.stdenv.mkDerivation {
	name = "alxr-pulse";
	version = "1.0.0";
	src = ./.;

    # https://github.com/ziglang/zig/issues/6810
	buildPhase = ''
		XDG_CACHE_HOME=".cache" zig build
	'';

	installPhase = ''
		mkdir -p $out/bin;
		cp zig-out/bin/waver-zig $out/bin/waver-zig;
	'';

	buildInputs = with pkgs; [
		zig
		zls
		pulseaudio
	];

	nativeBuildInputs = with pkgs; [
		pkg-config
	];
}
