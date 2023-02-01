{stdenv, fetchurl, jdk, makeWrapper, hadoop
, bash, coreutils, which, gawk, psutils, mysql_jdbc
, lib
}:

stdenv.mkDerivation rec {

	pname = "oozie";
	version = "5.2.1";
	src = fetchurl {
		url = "mirror://apache/oozie/${version}/oozie-${version}.tar.gz";
		sha256 = lib.fakeSha256;
	};
	
	buildInputs = [ maven ];
	nativeBuildInputs = [ jdk makeWrapper ];
	buildPhase = ''
  bin/mkdistro.sh
  '';
	installPhase = let
		untarDir = "${pname}-${version}";
	in ''
        # mkdir -p $out/{share,bin}
				mkdir $out
        mv * $out/

				for n in $(find $out{,/hcatalog}/bin -type f ! -name "*.*"); do
          wrapProgram "$n" \
            --set-default JAVA_HOME "${jdk.home}" \
						--set-default HIVE_HOME "$out" \
						--set-default HADOOP_HOME "${hadoop}/lib/${hadoop.untarDir}" \
            --prefix PATH : "${lib.makeBinPath [ bash coreutils which gawk psutils ]}"
	'';
}
