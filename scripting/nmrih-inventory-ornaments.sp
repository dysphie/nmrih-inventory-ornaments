
#define PREFIX "[-] "

#include <sdktools>
#include <sdkhooks>
#include <anymap>
#include <profiler>

#pragma semicolon 1

#define SOLID_NONE 0
#define COLLISION_GROUP_NONE 0

#define ASSERT(%1) if (!%1) ThrowError("#%1")

#define BODY_NOMAGLITE 1


#define SPECMODE_NONE 						0
#define SPECMODE_FIRSTPERSON 			4
#define SPECMODE_3RDPERSON 			5
#define SPECMODE_FREELOOK	 			6
#define SPECMODE_CSS_FIRSTPERSON 	3
#define SPECMODE_CSS_3RDPERSON 	4
#define SPECMODE_CSS_FREELOOK	 	5



ConVar cvDebugTransmit;

StringMap weaponRenderInfo;
StringMap weaponPlaceInfo;

enum struct WeaponPlaceInfo
{
	char attachment[32];
	float offset[3];
	float angles[3];
	float scale;
}

enum struct Renderer
{
	bool overridden;
	int propref;
	int activeLayer;

	void Delete()
	{
		PrintToServer("Renderer.Delete();");
		int prop = EntRefToEntIndex(this.propref);

		if (prop != -1)
			SafeRemoveEntity(prop);

		this.Init();
	}

	void Init()
	{
		PrintToServer("Renderer.Init();");
		this.propref = INVALID_ENT_REFERENCE;
		this.activeLayer = -1;
	}

	void Draw(int client, int weapon, int layer)
	{
		char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));
		PrintToServer("Renderer.Draw(%d. %d) [%s]", weapon, layer, classname);

		int prop = EntRefToEntIndex(this.propref);

		if (prop == -1)
		{
			PrintToServer("no prop, creating..");

			char model[PLATFORM_MAX_PATH];
			GetEntPropString(weapon, Prop_Data, "m_ModelName", model, sizeof(model));
		
			prop = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(prop, "model", model);
			DispatchKeyValue(prop, "spawnflags", "256");
			DispatchKeyValue(prop, "solid", "0");
			DispatchSpawn(prop);

			SDKHook(prop, SDKHook_SetTransmit, OnOrnamentTransmit);

			SetEntPropEnt(prop, Prop_Send, "m_hOwnerEntity", client);

			SetVariantString("!activator");
			AcceptEntityInput(prop, "SetParent", client);

			SetVariantString("HipAttachmentRight");
			AcceptEntityInput(prop, "SetParentAttachment");

			AcceptEntityInput(prop, "DisableShadows");

			this.propref = EntIndexToEntRef(prop);
		}
		
		// TeleportEntity(prop, .origin = {0.0, 0.0, 0.0}, .angles={0.0, 0.0, 0.0});
		WeaponPlaceInfo wpi;
		weaponPlaceInfo.GetArray(classname, wpi, sizeof(wpi));
		TeleportEntity(prop, .origin = wpi.offset, .angles = wpi.angles);

		SetEntPropFloat(prop, Prop_Send, "m_flModelScale", wpi.scale);

		PrintToServer("offset = %f %f %f, rotation = %f %f %f",
				wpi.offset[0],wpi.offset[1],wpi.offset[2],wpi.angles[0],wpi.angles[1],wpi.angles[2]);

		int modelIndex = GetModelIndex(weapon);
		SetModelIndex(prop, modelIndex);
		SetEntProp(prop, Prop_Send, "m_nBody", BODY_NOMAGLITE);
		// SetEntityModel(prop, "models/props_junk/watermelon01.mdl" );

		this.activeLayer = layer;
	}
}

// public Action OnCmdSpec(int client, int args)
// {
// 	int obsMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
// 	int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
// 	bool isspecing = IsSpectatingFirstPerson(client, 2);
// 	ReplyToCommand(client, "Specing %d with mode %d | %d", target, obsMode, isspecing);
// }

public Action OnOrnamentTransmit(int ornament, int transmitee)
{
	// TODO: opti?
	if (cvDebugTransmit.BoolValue)
		return Plugin_Continue;
	
	// Hide ornament to wearer
	int ornamentWearer = GetEntPropEnt(ornament, Prop_Data, "m_hOwnerEntity");
	if (transmitee == ornamentWearer)
		return Plugin_Handled;

	// Hide ornament to specs observing wearer in first person
	int observerMode = GetEntProp(transmitee, Prop_Send, "m_iObserverMode");
	if (observerMode != SPECMODE_FIRSTPERSON)
		return Plugin_Continue;

	int observerTarget = GetEntPropEnt(transmitee, Prop_Send, "m_hObserverTarget");
	if (observerTarget == ornamentWearer)
		return Plugin_Handled;

	return Plugin_Continue;
}

enum struct WeaponRenderInfo
{
	int rendererID;
	int layer;
}

ArrayList renderers[MAXPLAYERS+1];
Profiler prof;

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			DeleteClientRenderers(i);
}

void ParseConfig()
{
	char cfg[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, cfg, sizeof(cfg), "configs/inventory-ornaments.cfg");

	KeyValues kv = new KeyValues("Ornaments");
	if (!kv.ImportFromFile(cfg))
	{
		SetFailState("Couldn't read from \"%s\"", cfg);
	}

	if (!kv.GotoFirstSubKey())
	{
		delete kv;
		return;
	}

	int rendererID = 0;

	do
	{
		char rendererName[64];
		kv.GetSectionName(rendererName, sizeof(rendererName));
		PrintToServer("Parsing %s", rendererName);

		WeaponPlaceInfo baseWpi;
		kv.GetVector("offset", baseWpi.offset);
		kv.GetVector("rotation", baseWpi.angles);
		baseWpi.scale = kv.GetFloat("scale", 1.0);
		kv.GetString("attachment", baseWpi.attachment, sizeof(baseWpi.attachment));

		if (!kv.JumpToKey("items")) // Slot with no items, bail
			continue;

		if (!kv.GotoFirstSubKey()) // Slot with no items, bail
		{
			kv.GoBack();
			continue;
		}
		
		int layerID = 0;

		do
		{
			WeaponPlaceInfo itemWpi;

			char itemName[80];
			kv.GetSectionName(itemName, sizeof(itemName));


			kv.GetVector("offset", itemWpi.offset, baseWpi.offset);
			kv.GetVector("rotation", itemWpi.angles, baseWpi.angles);
			itemWpi.scale = kv.GetFloat("scale", baseWpi.scale);
			kv.GetString("attachment", itemWpi.attachment, sizeof(itemWpi.attachment), baseWpi.attachment);

			weaponPlaceInfo.SetArray(itemName, itemWpi, sizeof(itemWpi));

			WeaponRenderInfo itemWri;
			itemWri.rendererID = rendererID;
			itemWri.layer = layerID;

			weaponRenderInfo.SetArray(itemName, itemWri, sizeof(itemWri));
			PrintToServer("Assigning %s to renderer %d", itemName, itemWri.rendererID);

			layerID++;

		} while (kv.GotoNextKey());

		kv.GoBack();
		kv.GoBack();

		rendererID++;

	} while (kv.GotoNextKey());

	delete kv;

}

public void OnPluginStart()
{
	cvDebugTransmit = CreateConVar("ornament_always_transmit", "1");

	// RegConsoleCmd("sm_spec", OnCmdSpec);
	weaponRenderInfo = new StringMap();
	weaponPlaceInfo = new StringMap();	
	ParseConfig();

	prof = new Profiler();

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);

	HookEvent("player_death", OnPlayerDeath);
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		DeleteClientRenderers(client);
}

public void OnClientPutInServer(int client)
{
	InitClientRenderers(client);

	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
}


// TODO: Clean up on map end

void DeleteClientRenderers(int client)
{
	if (!renderers[client])
		return;

	int numRenderers = renderers[client].Length;
	Renderer renderer;
	for (int i; i < numRenderers; i++)
	{
		renderers[client].GetArray(i, renderer);
		renderer.Delete();
	}

	delete renderers[client];	
}

void InitClientRenderers(int client)
{
	ASSERT((renderers[client] == INVALID_HANDLE));

	renderers[client] = new ArrayList(sizeof(Renderer));

	for (int i; i < 3; i++)
	{
		Renderer r;
		r.Init();
		renderers[client].PushArray(r);
	}
}

// public void OnEntitySpawned(int entity, const char[] classname)
// {
// 	if (IsValidEdict(entity) && IsEntityWeapon(entity))
// 	{
// 		// TODO
// 	}
// }

public void OnClientDisconnect(int client)
{
	DeleteClientRenderers(client);
}

public Action OnWeaponDrop(int client, int weapon)
{
	if (weapon == -1)
		return Plugin_Continue;
	
	char name[64];
	GetEntityClassname(weapon, name, sizeof(name));

	PrintToServer("Drop %s", name);
	if (weapon != -1 && weapon != GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		OnWeaponUnholstered(client, weapon);

	return Plugin_Continue;
}

public void OnWeaponEquipPost(int client, int weapon)
{
	if (weapon != -1 && weapon != GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		OnWeaponHolstered(client, weapon);
}

public Action OnWeaponSwitch(int client, int weapon)
{
	int curWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	if (curWeapon == weapon)
		return Plugin_Continue;

	if (weapon != -1)
		OnWeaponUnholstered(client, weapon);

	if (curWeapon != -1)
		OnWeaponHolstered(client, curWeapon);

	// PrintToServer(PREFIX..."OnWeaponSwitch(%s to %s)", curName, name);
	return Plugin_Continue;
}

void OnWeaponHolstered(int client, int weapon)
{
	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));

	PrintToServer("OnWeaponHolstered(%N, %d) [%s]", client, weapon, classname);

	WeaponRenderInfo wri = {-1, -1};
	if (!weaponRenderInfo.GetArray(classname, wri, sizeof(wri)))
	{
		PrintToServer("Ignoring %s, no renderer for it", classname);
		return;
	}

	PrintToServer("weaponRenderInfo.GetArray(\"%s\", ...) -> {%d, %d}", classname, wri.rendererID, wri.layer);

	Renderer renderer;

	renderers[client].GetArray(wri.rendererID, renderer);

	PrintToServer("wri.layer(%d) <= renderer.activeLayer(%d)", wri.layer, renderer.activeLayer);
	if (renderer.activeLayer == -1 || wri.layer < renderer.activeLayer)
	{
		PrintToServer("Rendering because %s", renderer.activeLayer == -1 ? "nothing rn" :"better than existing");
	
		renderer.Draw(client, weapon, wri.layer);
		renderers[client].SetArray(wri.rendererID, renderer);
	}
}

void OnWeaponUnholstered(int client, int weapon)
{
	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));

	PrintToServer("OnWeaponUnholstered(%N, %d) [%s]", client, weapon, classname);

	WeaponRenderInfo wri = {-1, -1};
	if (!weaponRenderInfo.GetArray(classname, wri, sizeof(wri)))
	{
		return;
	}

	PrintToServer("weaponRenderInfo.GetArray(\"%s\", ...) -> {%d, %d}", classname, wri.rendererID, wri.layer);

	Renderer renderer; // ! This returns a new array
	renderers[client].GetArray(wri.rendererID, renderer);

	if (renderer.activeLayer == wri.layer)
	{
		int layer;
		int newWep = FindWeaponForRenderer(client, wri.rendererID, weapon, layer);
		if (newWep == -1)
		{
			PrintToServer("Out of things to render");
			renderer.Delete();
		}
		else
			renderer.Draw(client, newWep, layer);

		renderers[client].SetArray(wri.rendererID, renderer);	// ! So we must save it
	}
}

int FindWeaponForRenderer(int client, int rendererID, int except, int& layer)
{
	prof.Start();
	// PrintToServer("FindWeaponForRenderer(%N, %d, %d, %d)", client, rendererID);

	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	static int max;
	max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");

	int bestWeapon = -1;
	int lowestLayer = 9999999;

	int weapon;
	WeaponRenderInfo wri = {-1, -1};

	char classname[32];

	for(int i; i < max; i++)
	{
		weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon == except || weapon == -1 || weapon == activeWeapon) 
			continue;

		GetEntityClassname(weapon, classname, sizeof(classname));
		weaponRenderInfo.GetArray(classname, wri, sizeof(wri));

		if (wri.rendererID != rendererID)
			continue;

		if (wri.layer < lowestLayer)
		{
			lowestLayer = wri.layer;
			bestWeapon = weapon;
		}
	}

	if (bestWeapon != -1)
	{
		layer = lowestLayer;
		char class2[32];
		GetEntityClassname(bestWeapon, class2, sizeof(class2));
		PrintToServer("FindWeaponForRenderer -> %s", class2);
	}
	else
	{
		PrintToServer("FindWeaponForRenderer -> -1");
	}

	prof.Stop();
	PrintToServer("FindWeaponForRenderer %f", prof.Time);
	return bestWeapon;
}


void GetEntityModel(int entity, char[] buffer, int maxlen)
{
	GetEntPropString(entity, Prop_Data, "m_ModelName", buffer, maxlen);
}

int GetModelIndex(int entity)
{
	return GetEntProp(entity, Prop_Send, "m_iWorldModelIndex");
}

void SetModelIndex(int entity, int index)
{
	SetEntProp(entity, Prop_Send, "m_nModelIndex", index);
}

bool IsEntityWeapon(int entity)
{
	return HasEntProp(entity, Prop_Send, "_bloodCount");
}

void SafeRemoveEntity(int entity)
{
	ASSERT((entity > MaxClients+1));
	RemoveEntity(entity);
}
