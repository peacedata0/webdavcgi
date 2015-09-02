#!/bin/bash
#set -e
JS="jquery.js jquery-ui.js jquery.fileupload.js jquery.fancybox.pack.js jquery.fancybox-thumbs.js jquery.fancybox-buttons.js js.cookie.js multidraggable.js jquery.noty.js jquery.noty.layout.topCenter.js jquery.noty.themes.default.js jquery.hoverIntent.js"

CSS="jquery-ui.min.css jquery.fancybox.min.css jquery.fancybox-thumbs.min.css jquery.fancybox-buttons.min.css"
#jquery.powertip.min.css

concat() {
	src=$1
	dst=$2
	test -f "$src" && cat "$src" >> "$dst"
	test -f "$src.gz" && zcat "$src" >> "$dst"
}

for js in $JS ; do
	concat $js contrib.js
done
bash minify.sh contrib.js
rm contrib.js

test -f contrib.css && rm contrib.css
for css in $CSS ; do
	concat $css contrib.css
done
bash minify.sh contrib.css
rm contrib.css
