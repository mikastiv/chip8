with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "c env";
  buildInputs = [ SDL2 ];
}
