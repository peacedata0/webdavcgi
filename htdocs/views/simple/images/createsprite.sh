#!/bin/bash
## needs ImageMagick's montage

FILES="about.png addbookmark.png bookmarks.png copy.png cut.png delete.png download.png edit.png group.png paste.png refresh.png remove.png rename.png upload.png user-edit.png user-properties.png view-filter.png cancel.png createfolder.png createfile.png createlink.png changedir.png toggleselection.png logout.png help.png home.png add.png search.png settings.png refresh-start.png refresh-pause.png refresh-stop.png selectall.png selectnone.png contact.png"

test "$#" = "0" && exit 1
set=$1
cd set-$set

FILESWITHNULL="null: $(echo $FILES | sed -e 's@ @ null: @g')"
# with shadows:
#montage $FILESWITHNULL -tile 1x -shadow -background none -geometry 16x16+0+0 sprite.png
# without shadows:
montage $FILESWITHNULL -tile 1x -background none -geometry 16x16+2+2 -quality 100 sprite.png

i=1
for f in $FILES ; do
	echo $f -$(( $i * 40 - 25))
	i=$(( $i + 1 ))
done

mv sprite.png ..
