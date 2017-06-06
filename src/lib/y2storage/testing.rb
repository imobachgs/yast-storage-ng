require "yast"
require "y2storage"
require "y2storage/autoyast"

Yast.import "Profile"

Yast::Profile.ReadXML(ARGV[0])
partitioning = Yast::Profile.current["partitioning"]

devicegraph = Y2Storage::StorageManager.instance.y2storage_staging

supercoco = Y2Storage::Autoyast.new
supercoco.doit(devicegraph, partitioning)
