{ stdenv, fetchFromGitHub }:
stdenv.mkDerivation {
  name = "phytool";

  src = fetchFromGitHub {
    owner = "wkz";
    repo = "phytool";
    rev = "b8237fc69000d205ca0c59efe9462d3115077f6c";
    hash = "sha256-bjilgHX9rZBNUe6gRaLu3gW9a4vjx2Stq79slBwyBY8=";
  };

  installPhase = ''
    mkdir $out/bin -p
    make DESTDIR=$out PREFIX=/ install
  '';
}
