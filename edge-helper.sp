/*
 * edge-helper by rtldg
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>

#pragma newdecls required
#pragma semicolon 1

#define MINS view_as<float>({-16.0, -16.0, 0.0})
#define MAXS view_as<float>({16.0, 16.0, 0.0})
#define DOWN view_as<float>({89.0, 0.0, 0.0})

#define START_CHECKING 0.5
float gF_StartedOnGround[MAXPLAYERS+1];
int gI_LastDrawn[MAXPLAYERS+1];

int gI_DefaultBeam;
int gI_DefaultHalo;

Cookie gH_EdgeHelperCookie = null;

public void OnPluginStart()
{
	gH_EdgeHelperCookie = new Cookie("edgehelper", "Edge helper toggle", CookieAccess_Protected);
	RegConsoleCmd("sm_edgehelper", Command_EdgeHelper, "Edge helper toggle");
}

bool EdgeHelperEnabled(int client)
{
	char data[2];
	gH_EdgeHelperCookie.Get(client, data, sizeof(data));
	return !data[0] || (data[0] == '1');
}

public Action Command_EdgeHelper(int client, int args)
{
	bool bEdge = EdgeHelperEnabled(client);
	gH_EdgeHelperCookie.Set(client, (bEdge) ? "0" : "1");
	PrintToChat(client, (bEdge) ? ":(" : ":)");
	return Plugin_Handled;
}

public void OnMapStart()
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		gI_DefaultBeam = PrecacheModel("sprites/laser.vmt", true);
		gI_DefaultHalo = PrecacheModel("sprites/halo01.vmt", true);
	}
	else
	{
		gI_DefaultBeam = PrecacheModel("sprites/laserbeam.vmt", true);
		gI_DefaultHalo = PrecacheModel("sprites/glow01.vmt", true);
	}
}

public void OnClientPutInServer(int client)
{
	gF_StartedOnGround[client] = 0.0;
	gI_LastDrawn[client] = 0;
}

public bool NoPlayerFilter(int entity, int contentsMask)
{
	return !(0 < entity <= MaxClients);
}

#if 0
bool IsHullOnSomething(float origin[3])
{
	float endpoint[3];
	endpoint[0] = origin[0];
	endpoint[1] = origin[1];
	endpoint[2] = origin[2] - 0.1;
	TR_TraceHullFilter(origin, endpoint, MINS, MAXS, MASK_PLAYERSOLID, NoPlayerFilter);
	return TR_DidHit();
}

float HowFarFromSide(float origin[3], int idx, float add_this)
{
	float startpos[3];
	startpos = origin;

	for (int i = 0; i < 64; i++)
	{
		startpos[idx] += add_this;

		if (!IsHullOnSomething(startpos))
		{
			return 16.0 - (float(i) / 4);
		}
	}

	return 0.0;
}

void FillPoints(float origin[3], float dist[4], float startpoint[3], float endpoint[3])
{
	startpoint = origin;
	endpoint = origin;

	if (dist[0] != 0.0)
	{
		startpoint[0] -= 16.0 - dist[0];
		endpoint[0] += dist[0];
	}

	if (dist[1] != 0.0)
	{
		startpoint[1] += 16.0 - dist[1];
		endpoint[1] -= dist[1];
	}

	if (dist[2] != 0.0)
	{
		startpoint[0] -= 16.0 - dist[2];
		endpoint[0] += dist[2];
	}

	if (dist[3] != 0.0)
	{
		startpoint[1] += 16.0 - dist[3];
		endpoint[1] -= dist[3];
	}

	if (dist[0] != 0.0 || dist[2] != 0.0)
	{
		startpoint[0] -= 1.0;
	}

	if (dist[1] != 0.0 || dist[3] != 0.0)
	{
		startpoint[1] -= 1.0;
	}
}
#endif

void FillBboxPoints(float origin[3], float square[4][3])
{
	static float mmtable[4][3] = {
		{-16.0, 16.0, 0.0},  // topleft
		{16.0, 16.0, 0.0},   // topright
		{-16.0, -16.0, 0.0}, // bottom left
		{16.0, -16.0, 0.0},  // bottom right
	};

	for (int i = 0; i < 4; i++)
	{
		for (int x = 0; x < 3; x++)
		{
			square[i][x] = origin[x] + mmtable[i][x];
		}
	}
}

void DrawBeam(int client, float startpoint[3], float endpoint[3])
{
	TE_SetupBeamPoints(
		startpoint,
		endpoint,
		gI_DefaultBeam,
		gI_DefaultHalo,
		0, // start frame
		0, // frame rate
		0.2, // life
		0.25, // width
		1.0, // EndWidth
		0, // FadeLength
		0.0, // Amplitude
		{255, 153, 255, 75}, // color
		0 // speed
	);

	TE_SendToClient(client);
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client))
	{
		return;
	}

	if (!EdgeHelperEnabled(client))
	{
		return;
	}

	if (!(GetEntityFlags(client) & FL_ONGROUND) || !(buttons & IN_DUCK))
	{
		gF_StartedOnGround[client] = 0.0;
		return;
	}

	if (gF_StartedOnGround[client] == 0.0)
	{
		gF_StartedOnGround[client] = GetEngineTime();
	}

	if (GetEngineTime() - gF_StartedOnGround[client] < 0.5)
	{
		return;
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);

	TR_TraceRayFilter(origin, DOWN, MASK_PLAYERSOLID, RayType_Infinite, NoPlayerFilter);

	if (!TR_DidHit()) // odd
	{
		return;
	}

	float lower[3];
	TR_GetEndPosition(lower);

	if ((origin[2] - lower[2]) <= 0.0)
	{
		return;
	}

#if 0
	float dist[4];
	dist[0] = HowFarFromSide(origin, 0, 0.25);
	dist[1] = HowFarFromSide(origin, 1, -0.25);
	dist[2] = HowFarFromSide(origin, 0, -0.25);
	dist[3] = HowFarFromSide(origin, 1, 0.25);

	if (dist[0] == 0.0 && dist[1] == 0.0 && dist[2] == 0.0 && dist[3] == 0.0)
	{
		return;
	}

	PrintToConsole(client, "%f %f %f %f", dist[0], dist[1], dist[2], dist[3]);
#endif

	int total_ticks = GetGameTickCount();

	if ((total_ticks - gI_LastDrawn[client]) < 2)
	{
		return;
	}

	gI_LastDrawn[client] = total_ticks;

#if 0
	float startpoint[3], endpoint[3];
	FillPoints(origin, dist, startpoint, endpoint);
	DrawBeam(client, startpoint, endpoint);
#endif

	origin[2] += 1.0;

	float square[4][3];
	FillBboxPoints(origin, square);
	DrawBeam(client, square[0], square[1]); // topleft to topright
	DrawBeam(client, square[0], square[2]); // topleft to bottomleft
	DrawBeam(client, square[2], square[3]); // bottomleft to bottomright
	DrawBeam(client, square[1], square[3]); // topright to bottright
}
