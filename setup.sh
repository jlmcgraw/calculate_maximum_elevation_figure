#!/bin/bash
set -eu               # Abort on error or unset variables
IFS=$(printf '\n\t')  # File separator is newline or tab

#Install necessary software
sudo \
    apt-get \
        install \
            cpanminus \
            Carton \
            perltidy \
            gdal-bin

#Install the libraries in our cpanfile locally
carton install

if [ -d .git ];
    then
        #Setup hooks to run perltidy on git commit
        cat <<- 'EOF' > .git/hooks/pre-commit
        #!/bin/bash
        find . \
            -maxdepth 1 \
            -type f \
            \( -iname '*.pl' -or -iname '*.pm' \) \
            -print0 \
                |
                xargs \
                    -0 \
                    -I{} \
                    -P0 \
                    sh -c 'perltidy --perl-best-practices -nst -b {}'
EOF
fi
    
chmod +x .git/hooks/pre-commit

echo "Usage: carton exec calculate_mef.pl <directory_with_SRTM files>"