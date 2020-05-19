#include <amxmodx>
#include <fun>
#include <cstrike>
#include <fakemeta>
#include <engine>
#include <hamsandwich>

#define VERSION "1.1"

#pragma semicolon 1;

#define IsPlayer(%1)            (1 <= %1 <= g_iMaxPlayers)

#define SB_ATTRIB_DEAD          1<<0

// --| Macros
#define get_bit(%1,%2) 		( %1 &   1 << ( %2 & 31 ) )
#define set_bit(%1,%2)	 	%1 |=  ( 1 << ( %2 & 31 ) )
#define clear_bit(%1,%2)	%1 &= ~( 1 << ( %2 & 31 ) )

#define GetPlayerHullSize(%1)  ( ( pev ( %1, pev_flags ) & FL_DUCKING ) ? HULL_HEAD : HULL_HUMAN )
//Credits to Emp`
#define LoopThroughAlivePlayers(%1) new %1;while( (%1=NextAlivePlayer(%1)) )

// --| The first search distance for finding a free location in the map.
#define START_DISTANCE    32   
// --| How many times to search in an area for a free space.
#define MAX_ATTEMPTS      128  

// --| Just for readability.
enum Coord_e { Float:x, Float:y, Float:z };

new g_iMaxPlayers;
new g_iMsgSayText;
new g_iItemsMenu;
new g_iLargestPlayer;
new g_iDeathFlag;
new g_iScoreBoard;

new g_bUserDead;
new g_bUserReady;
new g_bIsNoMore;
new g_bHasMenuOpen;
new g_bGravity;
new g_bNoClip;
new g_bSpeed;

new bool:g_bRoundEnd;

new Float:vecOrigin[3];

public plugin_init()
{
	register_plugin("Alive When Dead", VERSION, "Pastout!");
	register_cvar("author", "Pastout!", FCVAR_SPONLY);
	register_cvar("version", VERSION, FCVAR_SPONLY);
	
	RegisterHam(Ham_Killed, "player", "Ham_PlayerKilled_Post", 1);
	RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Post", 1);
	RegisterHam(Ham_Player_PreThink, "player", "Ham_CBasePlayer_PreThink_Post", 1);
	
	register_forward(FM_AddToFullPack, "Fwd_AddToFullPack_Post", 1);
	
	// --| Variables
	g_iMaxPlayers = get_maxplayers();
	g_iMsgSayText = get_user_msgid("SayText");
	g_iScoreBoard = get_user_msgid("ScoreAttrib");
	
	register_message(g_iScoreBoard, "MsgScoreBoard");
	
	// --| Client Commands
	new command[] = "CmdMainMenu";
	register_clcmd("say /gez", command);
	register_clcmd("say_team /gez", command);
	set_task(90.0, "gez_bilgilendirme", 0);
	
	register_event("HLTV", "ev_NewRound", "a", "1=0", "2=0");
	register_logevent("ev_RoundEnd",2,"1=Round_End");
}
public gez_bilgilendirme()
{
		renkli_yazi(0,"!n[!t/gez!n] !gYazarak Oluyken Gezebilirsiniz.");
		set_task(90.0, "gez_bilgilendirme", 0);
}
public ev_NewRound()
	g_bRoundEnd = false;
	
public ev_RoundEnd()
	g_bRoundEnd = true;

public client_disconnect(id)
{
	Reset_all(id);
	if( g_iLargestPlayer == id )
	{
		g_iLargestPlayer = 0;
		for( new i = id - 1; i > 0; i-- )
		{
			g_iLargestPlayer = i;
			break;
		}
	}
}

public client_putinserver(id)
{
	Reset_all(id);
	g_iLargestPlayer = max( g_iLargestPlayer, id );
}

public MsgScoreBoard()
{
	new id = get_msg_arg_int(1);
	
	if(get_bit(g_bUserDead, id))
		set_msg_arg_int(2, ARG_BYTE, SB_ATTRIB_DEAD);
}

public Ham_PlayerKilled_Post(victim, attacker, shouldgib)
{	
	if (!is_user_connected(victim))
		return HAM_IGNORED;
	
	// --| Update the scoreboard
	new szDeaths;
	szDeaths = cs_get_user_deaths(victim);
	cs_set_user_deaths(victim, szDeaths);

	if(is_user_connected(attacker))
	{
		szDeaths = cs_get_user_deaths(attacker);
		cs_set_user_deaths(attacker, szDeaths);
	}
	
	if(!g_bRoundEnd)
	{
		if(victim == attacker)
		{
			if (get_bit(g_bUserDead, victim))
			{
				clear_bit(g_bGravity, victim);
				clear_bit(g_bNoClip, victim);
				clear_bit(g_bSpeed, victim);
				if (get_bit(g_bHasMenuOpen, victim))
				{
					if(player_menu_info(victim, g_iItemsMenu, g_iItemsMenu))
					{
						menu_cancel(victim);
						client_cmd(victim, "slot1");
					}
					clear_bit(g_bHasMenuOpen, victim);
				}	
			}
		}
		else
		{
			if(!get_bit(g_bUserDead, victim) && !get_bit(g_bIsNoMore, victim))
			{
				
				entity_get_vector(victim, EV_VEC_origin, vecOrigin);
				
				if(GetPlayerHullSize(victim) == HULL_HEAD)
					vecOrigin[2] += 15;
				else
					vecOrigin[2] += 30;
					
				set_task(2.0, "RespawnPlayer", victim);
			}
		}
	}
	
	return HAM_IGNORED;
}

public RespawnPlayer(victim)
{
	if(!g_bRoundEnd)
	{
		set_bit(g_iDeathFlag, victim);	
		
		set_bit(g_bUserDead, victim);
		clear_bit(g_bUserReady, victim);
		
		// --| Respawn Player at Deadbody
		ExecuteHamB(Ham_CS_RoundRespawn, victim);
		
		entity_set_vector(victim, EV_VEC_origin, vecOrigin);
		
		ClientCommand_UnStuck(victim);
		
		// --| Show Dead Menu Items
		CmdMainMenu(victim);
	
		// --| Set The Victims Flags to DEAD_RESPAWNABLE
		entity_set_int(victim, EV_INT_deadflag, DEAD_RESPAWNABLE);
	}
}

public Ham_PlayerSpawn_Post(id)
{ 
	if (!is_user_alive(id))
		return HAM_IGNORED;		
		
	if (get_bit(g_iDeathFlag, id))
		entity_set_int(id, EV_INT_deadflag, DEAD_RESPAWNABLE);	

	if (get_bit(g_bUserReady, id))
	{
		clear_bit(g_bUserDead, id);
		clear_bit(g_bIsNoMore, id);
		clear_bit(g_bGravity, id);
		clear_bit(g_bNoClip, id);
		clear_bit(g_bSpeed, id);
		message_begin(MSG_ONE_UNRELIABLE, g_iScoreBoard, _, id);
		write_byte(id);
		write_byte(0);
		message_end();
		if (get_bit(g_bHasMenuOpen, id))
		{
			if(player_menu_info(id, g_iItemsMenu, g_iItemsMenu))
			{
				menu_cancel(id);
				client_cmd(id, "slot1");
			}
			clear_bit(g_bHasMenuOpen, id);
		}
	}

	set_bit(g_bUserReady, id);
	clear_bit(g_iDeathFlag, id);
	set_task(3.0,"kontrolet",id);
	return HAM_IGNORED;
}
public kontrolet(id)
{
	if (!is_user_alive(id))
		return HAM_IGNORED;		
		
	if (get_bit(g_iDeathFlag, id))
		entity_set_int(id, EV_INT_deadflag, DEAD_RESPAWNABLE);	

	if (get_bit(g_bUserReady, id))
	{
		clear_bit(g_bUserDead, id);
		clear_bit(g_bIsNoMore, id);
		clear_bit(g_bGravity, id);
		clear_bit(g_bNoClip, id);
		clear_bit(g_bSpeed, id);
		message_begin(MSG_ONE_UNRELIABLE, g_iScoreBoard, _, id);
		write_byte(id);
		write_byte(0);
		message_end();
		if (get_bit(g_bHasMenuOpen, id))
		{
			if(player_menu_info(id, g_iItemsMenu, g_iItemsMenu))
			{
				menu_cancel(id);
				client_cmd(id, "slot1");
			}
			clear_bit(g_bHasMenuOpen, id);
		}
	}

	set_bit(g_bUserReady, id);
	clear_bit(g_iDeathFlag, id);
	return PLUGIN_HANDLED;
}
public Fwd_AddToFullPack_Post(es, e, iEnt, id, hostflags, player, pSet)
{
	if( player && id != iEnt )
	{
		if(get_bit(g_bUserDead, id))
		{
			set_es(es, ES_Solid, SOLID_NOT);
			if( get_bit(g_bUserDead, iEnt) )
			{
				set_es(es, ES_RenderMode, kRenderTransAdd);
				set_es(es, ES_RenderAmt, 80);
				set_es(es, ES_RenderColor, 0, 0, 0);
				set_es(es, ES_RenderFx, kRenderFxDeadPlayer);
			}
		}
		else if(get_bit(g_bUserDead, iEnt) )
		{
			set_es(es, ES_Solid, SOLID_NOT);
			set_es(es, ES_Effects, get_es(es, ES_Effects) | EF_NODRAW);
			set_es(es, ES_Origin, Float:{99999.9,99999.9,99999.9});
		}
	}
}

public Ham_CBasePlayer_PreThink_Post(id)
{
	// --| Is alive, ignore.
	if( !get_bit(g_bUserDead, id) )
		return;
	
	if(get_bit(g_bUserDead, id))
		set_pev( id, pev_solid, SOLID_NOT );
		
	LoopThroughAlivePlayers( iPlayer )
		if( id != iPlayer )
			set_pev( iPlayer, pev_solid, SOLID_NOT );
}

public client_PostThink(id)
{
	// --| Is alive, ignore.
	if( !get_bit(g_bUserDead, id) )
		return;
		
	if(get_bit(g_bUserDead, id))
		set_pev( id, pev_solid, SOLID_SLIDEBOX );

	LoopThroughAlivePlayers( iPlayer )
		if( id != iPlayer )
			set_pev( iPlayer, pev_solid, SOLID_SLIDEBOX );
}

public ClientCommand_UnStuck( const id )
{
	new i_Value;

	if ( ( i_Value = UTIL_UnstuckPlayer ( id, START_DISTANCE, MAX_ATTEMPTS ) ) != 1 )
		switch ( i_Value )
		{
			case 0: renkli_yazi(id, "Couldn't find a free spot to move you too");
			case -1: renkli_yazi(id, "!n[!tCoonquaR!n] !gBu Menuyu Kullanmak Icin Gezinti Modunda Acmaniz Gerekmektedir.");
		}

	return PLUGIN_CONTINUE;
}


UTIL_UnstuckPlayer( const id, const i_StartDistance, const i_MaxAttempts )
{
	// --| Is alive, ignore.
	if ( !get_bit(g_bUserDead, id) )  return -1;
	
	static Float:vf_OriginalOrigin[ Coord_e ], Float:vf_NewOrigin[ Coord_e ];
	static i_Attempts, i_Distance;
	
	// --| Get the current player's origin.
	pev ( id, pev_origin, vf_OriginalOrigin );
	
	i_Distance = i_StartDistance;

	while ( i_Distance < 1000 )
	{
		i_Attempts = i_MaxAttempts;
	
		while ( i_Attempts-- )
		{
			vf_NewOrigin[ x ] = random_float ( vf_OriginalOrigin[ x ] - i_Distance, vf_OriginalOrigin[ x ] + i_Distance );
			vf_NewOrigin[ y ] = random_float ( vf_OriginalOrigin[ y ] - i_Distance, vf_OriginalOrigin[ y ] + i_Distance );
			vf_NewOrigin[ z ] = random_float ( vf_OriginalOrigin[ z ] - i_Distance, vf_OriginalOrigin[ z ] + i_Distance );
		
			engfunc ( EngFunc_TraceHull, vf_NewOrigin, vf_NewOrigin, DONT_IGNORE_MONSTERS, GetPlayerHullSize ( id ), id, 0 );
		
			// --| Free space found.
			if ( get_tr2 ( 0, TR_InOpen ) && !get_tr2 ( 0, TR_AllSolid ) && !get_tr2 ( 0, TR_StartSolid ) )
			{
				// --| Set the new origin .
				engfunc ( EngFunc_SetOrigin, id, vf_NewOrigin );
				return 1;
			}
		}
	
		i_Distance += i_StartDistance;
	}

	// --| Could not be found.
	return 0;
}  

NextAlivePlayer(id)
{
	do id++;
	while( id <= g_iLargestPlayer && !is_user_alive( id ) );
	return ( id <= g_iLargestPlayer ) ? id : 0;
}

public CmdMainMenu(id)
{
	if(!get_bit(g_bUserDead, id) && is_user_alive(id))
	{
		renkli_yazi(id, "!n[!tCoonquaR!n] !gBu Menuye Sadece Oluler Girebilir.");
		return PLUGIN_HANDLED;
	}
		
	set_bit(g_bHasMenuOpen, id);
	
	// --| Menu Title
	new szText[777 char];
	formatex(szText, charsmax(szText), "\d[\yCoonquaR\d] : [\rGezinme Modu\d]");
	
	// --| Create the menu
	g_iItemsMenu = menu_create(szText, "StartMenu_Handle");
	
	formatex(szText, charsmax(szText), "\d[\yGravity\d] : [\r%s\d]", get_bit(g_bGravity, id) ? "ACIK" : "KAPALI" );
	menu_additem(g_iItemsMenu, szText, "1", 0);
	
	formatex(szText, charsmax(szText), "\d[\yNoclip\d] : [\r%s\d]", get_bit(g_bNoClip, id) ? "ACIK" : "KAPALI" );
	menu_additem(g_iItemsMenu, szText, "2", 0);
	
	formatex(szText, charsmax(szText), "\d[\ySpeed\d] : [\r%s\d]", get_bit(g_bSpeed, id) ? "ACIK" : "KAPALI" );
	menu_additem(g_iItemsMenu, szText, "3", 0);
	
	formatex(szText, charsmax(szText), "\d[\yStuck\d]");
	menu_additem(g_iItemsMenu, szText, "4", 0);
	
	formatex(szText, charsmax(szText), "\d[\yGezinme Modunu Ac\d]", get_bit(g_bUserDead, id));
	menu_additem(g_iItemsMenu, szText, "5", 0);
	
	menu_setprop(g_iItemsMenu,MPROP_EXITNAME,"\d[\rCikis\d]");
	menu_setprop(g_iItemsMenu, MPROP_EXIT, MEXIT_ALL);
	menu_display(id, g_iItemsMenu);
	
	return PLUGIN_HANDLED;
}

public StartMenu_Handle(id, g_iItemsMenu, item)
{
	if(item == MENU_EXIT)
	{
		clear_bit(g_bHasMenuOpen, id);
		menu_destroy(g_iItemsMenu);
		return PLUGIN_HANDLED;
	}
	
	if(!get_bit(g_bUserDead, id) && is_user_alive(id))
	{
		clear_bit(g_bHasMenuOpen, id);
		renkli_yazi(id, "!n[!tCoonquaR!n] !gBu Menuye Sadece Oluler Girebilir.");
		return PLUGIN_HANDLED;
	}
	
	new data[6], iName[64];
	new access, callback;
	
	menu_item_getinfo(g_iItemsMenu, item, access, data, 5, iName, 63, callback);
	
	new key = str_to_num(data);
	switch(key)
	{
		case 1:{ ToggleGravity(id);CmdMainMenu(id); }
		case 2:{ ToggleNoClip(id);CmdMainMenu(id); }
		case 3:{ ToggleSpeed(id);CmdMainMenu(id); }
		case 4:{ ClientCommand_UnStuck(id);CmdMainMenu(id); }
		case 5:{ ToggleGhost(id);CmdMainMenu(id); }
	}
	return PLUGIN_HANDLED;
}

ToggleGravity(id)
{
	// --| Make sure player is dead
	if (get_bit(g_bUserDead, id))
		// --| If player has gravity
		if (get_bit(g_bGravity, id))
		{
			// --| Turn off gravity for player
			set_user_gravity(id, 1.0);
			clear_bit(g_bGravity, id);
		}
		else
		{
			// --| Turn on gravity for player
			set_user_gravity(id, 0.5);
			set_bit(g_bGravity, id);
		}
}

ToggleNoClip(id)
{
	// --| Make sure player is dead
	if (get_bit(g_bUserDead, id))
		// --| If player has noclip
		if (get_user_noclip(id))
		{
			// --| Turn off noclip for player
			set_user_noclip(id, 0);
			clear_bit(g_bNoClip, id);
			// --| Check if player is stuck
			ClientCommand_UnStuck(id);
		}
		else
		{
			// --| Turn on noclip for player
			set_user_noclip(id, 1);
			set_bit(g_bNoClip, id);
		}
}

ToggleSpeed(id)
{
	// --| Make sure player is dead
	if (get_bit(g_bUserDead, id))
		// --| If player has speed
		if (get_bit(g_bSpeed, id))
		{
			// --| Turn off speed for player
			set_user_maxspeed(id, 250.0);
			clear_bit(g_bSpeed, id);
		}
		else
		{
			// --| Turn on speed for player
			set_user_maxspeed(id, 600.0);
			set_bit(g_bSpeed, id);
		}
}
		
ToggleGhost(id)
{
	if(!get_bit(g_bIsNoMore, id))
		RespawnPlayer(id);
}

public Allow_Reset(id)
	clear_bit(g_bIsNoMore, id);

public Reset_all(id)
{ 	
	clear_bit(g_iDeathFlag, id);
	clear_bit(g_bUserDead, id);
	clear_bit(g_bUserReady, id);
	clear_bit(g_bIsNoMore, id);
	clear_bit(g_bHasMenuOpen, id);
	clear_bit(g_bGravity, id);
	clear_bit(g_bNoClip, id);
	clear_bit(g_bSpeed, id);
}
stock renkli_yazi(const id, const input[], any:...)
{
	new count = 1, players[32];
	static msg[191];
	vformat(msg, 190, input, 3);
	
	replace_all(msg, 190, "!n", "^x01"); // Default Renk(Sarı)
	replace_all(msg, 190, "!g", "^x04"); // Yeşil Renk
	replace_all(msg, 190, "!t", "^x03"); // Takım Renk( CT mavi , T kırmızı )
	
	if (id) players[0] = id; else get_players(players, count, "ch");
	{
		for (new i = 0; i < count; i++)
		{
			if (is_user_connected(players[i]))
			{
				
				message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("SayText"), _, players[i]);
				write_byte(players[i]);
				write_string(msg);
				message_end();
			}

		}
	}
} 
