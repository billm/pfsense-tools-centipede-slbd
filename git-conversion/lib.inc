CONVERSIONDIR=/home/${USER}/conversion
CVSMODULE=pfSense
CVSSRC=cvs.pfsense.org:/cvsroot/
CVSDST=${CONVERSIONDIR}/cvsroot/
GITDST=git@rcs.pfsense.org:pfsense-import-test-minus-binaries/mainline.git

# sync over the repo
sync_from_cvs() {
	rsync -avz --delete ${CVSSRC} ${CVSDST}
}

# Remove cruft that's been deleted
purge_repo() {
	find ${CONVERSIONDIR}/cvsroot/${CVSMODULE} -name "Attic" -type d -exec rm -rf {} \;
}

cvs_to_git() {
	git cvsimport -k -i -d ${CONVERSIONDIR}/cvsroot -C ${CVSMODULE}-git -A ${CONVERSIONDIR}/author-conf-file ${CVSMODULE}
}

update_pfSense_gitorious() {
	cd ${CONVERSIONDIR}/pfSense-git
	git push --mirror origin
}

init_pfSense_gitorious() {
	cd ${CONVERSIONDIR}/pfSense-git
	# Swap branches around
	git branch -m master deprecated/oldHEAD
	git branch -M RELENG_1 master
	# This shouldn't be pushed, we'll just delete it
	# It's Ermal's old dev branch
	git branch -D RELENG_1_2_RELEASE_BRANCH
	# There are a few deletable branches that we should rm here
	#
	# Any other config changes needed before pushing?
	# What about that utf thingy?
	# You may want to amend it after fixing the message, or set the config
	# variable i18n.commitencoding to the encoding your project uses.
	#
	# Add remote repo for pushing to
	git remote add origin ${GITDST}
	# to push the master branch to the origin remote we added above:
	git push --mirror origin
}