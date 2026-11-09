class_name MalletVersion
extends RefCounted
## The one place MALLET's version lives. 0.x = previews: the middle number goes up with each batch of new
## features, the last with bug-fix releases. 1.0 is the first release we call complete (the MVP).

const VERSION := "0.17.11"
const CHANNEL := "preview"


static func full() -> String:
	return "MALLET %s %s" % [VERSION, CHANNEL]
