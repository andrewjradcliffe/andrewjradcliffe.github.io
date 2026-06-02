EMACS   ?= emacs
PUBLISH := site/publish.el
PUBDIR  := public
PORT    ?= 8000

.PHONY: publish serve clean

## Build the whole site into public/
publish:
	$(EMACS) --batch -l $(PUBLISH) -f org-publish-all

## Build, then serve public/ locally
serve: publish
	cd $(PUBDIR) && python3 -m http.server $(PORT)

## Remove build output and Org timestamp cache
clean:
	rm -rf $(PUBDIR) .org-timestamps
