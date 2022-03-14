{stdenv, fetchurl, jdk, makeWrapper, hadoop
, bash, coreutils, which
, lib
}:

stdenv.mkDerivation rec {

	pname = "hive";
	version = "2.3.9";
	src = fetchurl {
		url = "mirror://apache/hive/hive-${version}/apache-hive-${version}-bin.tar.gz";
		sha256 = "sha256-GZYyfJZnLn6o6qj8Y5csdbwJUoejJhLlReDlHBYiy1w=";
	};
	
	nativeBuildInputs = [ makeWrapper ];
	
	installPhase = let
		untarDir = "${pname}-${version}";
	in ''
        # mkdir -p $out/{share,bin}
				mkdir $out
        mv * $out/

				for n in $(find $out{,/hcatalog}/bin -type f ! -name "*.*"); do
          makeWrapper "$n" "$out/bin/$(basename $n)"\
            --set-default JAVA_HOME "${jdk.home}" \
						--set-default HIVE_HOME "$out" \
						--set-default HADOOP_HOME "${hadoop}/lib/${hadoop.untarDir}" \
            --prefix PATH : "${lib.makeBinPath [ bash coreutils which]}"
				done
	'';
}
