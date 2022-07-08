# Inventory Ornaments
[Sourcemod](https://www.sourcemod.net) plugin for [No More Room in Hell](https://store.steampowered.com/app/224260) that adds the ability to display holstered items on survivor models. 

![nmrih_xr3KdG57OL](https://user-images.githubusercontent.com/11559683/116795572-632e2f00-aaac-11eb-94cb-7d799fc72e7e.png)

## Installation
- [Install Sourcemod](https://wiki.alliedmods.net/Installing_sourcemod) (1.11.0.6506 or higher is recommended for full functionality)
- Grab the latest zip from the [releases](https://github.com/dysphie/nmrih-inventory-ornaments/releases) section.
- Extract the contents into `addons/sourcemod`
- Refresh the plugin list (`sm plugins refresh` or `sm plugins reload nmrih-inventory-ornaments` in server console)

## Rendering
By default there are 3 renderers, each displaying a different set of items, with item render priority decreasing from left to right.

**Right hip:** First Aid Kit, Bandages

**Left hip:** Gene Therapy, Pills

**Back**: Welder, Extinguisher, Abrasive Saw, Chainsaw, Pickaxe, Sledge, Fubar, Machete, Hatchet, Shovel, Fire Axe, E-Tool, Lead Pipe, Crowbar, Baseball Bat 

The different renderers, item positions and priorities can be tweaked in `configs/inventory-ornaments.cfg` (Ideally, this will be editable through a menu in the future).
Structure is as follows:
```cpp
"Ornaments"
{
	"Leg" // REQUIRED: Renderer name, can be anything unique
	{
		// REQUIRED: Items will attach to this point in the player model
		"attachment" 	"HipAttachmentRight"

		// OPTIONAL: Items offset (x, y, z) from attachment point's origin
		"offset"			"15.2 60.2 8.0"				

		// OPTIONAL: Items rotation (x, y, z) from attachment point's angles
		"rotation"		"35.0 23.2 0.0"				

		// OPTIONAL: Items will be scaled by this amount (twice as big in this case)
		"scale" 			"2.0"									

		// REQUIRED: List of item classnames that this renderer will display. 
		// Items at the top take render priority over the rest
		"items"		
		{
			"item_gene_therapy"	//  REQUIRED: Item classname
			{
				// OPTIONAL: Overrides the default offset for this item
				"offset"		  "1.0 20.0 9.2"

				// OPTIONAL: Overrides default rotation for this item
				"rotation"		"0.0 90.0 0.0"

				// OPTIONAL: Overrides model scale for this item
				"scale"       "1.0"               
			}

			"item_bandages" {}	// Body can be left empty
		}
	}
}
```

**Note that due to the way these items are rendered, they can take quite a toll on server performance (SetTransmit is pretty expensive). You should try to keep the number of renderers on a player at less than 5 at all times**
