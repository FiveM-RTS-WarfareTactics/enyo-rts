Config.Bots = {
    
    { id = "bot_viper", name = "Viper_Tactical [AI]", saveChance = 75, aggroRange = 75.0 },
    { id = "bot_ghost", name = "Ghost_Recon_01 [AI]", saveChance = 80, aggroRange = 60.0 },
    { id = "bot_spectre", name = "Spectre_Ops [AI]", saveChance = 70, aggroRange = 80.0 }, 
    
    { id = "bot_bowie", name = "BowieKnife99 [AI]", saveChance = 65, aggroRange = 90.0 },
    { id = "bot_forza", name = "SkillIssue_66 [AI]", saveChance = 60, aggroRange = 100.0 },
    
    { id = "bot_tryhard", name = "xX_NoobSlayer_Xx [AI]", saveChance = 60, aggroRange = 95.0 },
    { id = "bot_troll", name = "DontClickMyLink [AI]", saveChance = 65, aggroRange = 100.0 },
    { id = "bot_runner", name = "CantCatchMe_00 [AI]", saveChance = 70, aggroRange = 85.0 },
    { id = "bot_glitch", name = "LagSwitchPro [AI]", saveChance = 75, aggroRange = 70.0 }
}

Config.BotChatter = {
    ["bot_troll"] = {
        start = {
            "lmaooo ur actually gonna try huh",
            "bro u queued into the wrong guy",
            "glhf u gonna need it trust",
            "already know how this ends for u ??"
        },
        timeWarning = {
            "bro stop hiding and FIGHT ME",
            "times almost up and ur still doing nothing??",
            "tick tock buddy the clock don't care",
            "are u afk or just actually this bad"
        },
        nearWin = {
            "lol ur actually cooked rn",
            "its over just ff bro",
            "this is genuinely embarrassing to watch",
            "sit. down."
        },
        nearLose = {
            "nah ur hacking there's no way",
            "ok that was lucky not skill",
            "this server is actually trash",
            "go touch grass after u get this W ur gonna need it"
        },
        obj_win = {
            "that's mine now thanks",
            "free resources lmao",
            "couldn't even hold that? yikes"
        },
        obj_lose = {
            "i let u have that one don't get excited",
            "enjoy it while it lasts lol",
            "ok fine u got that ONE"
        }
    },

    ["bot_ghost"] = {
        start = {
            "gl, don't make this boring",
            "let's see what ur opening looks like",
            "show me something good",
            "first platoon's down, ur move"
        },
        timeWarning = {
            "ur running out of time to do anything",
            "clock's going and ur still not on the point",
            "u gonna push or just sit there",
            "less than a minute and ur losing"
        },
        nearWin = {
            "gg, almost done here",
            "u tried, i'll give u that",
            "wasn't even close at the end",
            "gg wp"
        },
        nearLose = {
            "didn't expect that from u honestly",
            "good play, won't let it happen again",
            "u caught me off guard, not again",
            "alright ur better than i thought"
        },
        obj_win = {
            "that point's mine now, good luck",
            "ur resources are drying up",
            "i own that sector now"
        },
        obj_lose = {
            "enjoy that point while u can",
            "u won't hold it long",
            "fine, u got that one"
        }
    },

    ["bot_bowie"] = {
        start = {
            "let's gooo glhf man",
            "good luck out there don't hold back",
            "first platoon's down, come on then",
            "alright let's see what u got"
        },
        timeWarning = {
            "one minute!! get on the point!!",
            "bro ur running outta time hurry up",
            "clock's going u gotta make a move NOW",
            "last chance to take that point let's go"
        },
        nearWin = {
            "GG man honestly good game",
            "gg wp u made me work for it",
            "almost had me at the end ngl",
            "good game bro, rematch?"
        },
        nearLose = {
            "aw man that was clean from u",
            "niceeee play bro respect",
            "ok ok i see u",
            "that was a good move i'll admit it"
        },
        obj_win = {
            "grabbed ur side point, pushing now",
            "ur resources are mine soz",
            "that flank is locked down"
        },
        obj_lose = {
            "fine u got the point, won't last",
            "ur on the point but can u hold it",
            "good cap but i'm coming for it"
        }
    },

    ["bot_viper"] = {
        start = {
            "gl, ur gonna need to be sharp",
            "show me ur opening move",
            "let's go",
            "first platoon's down, don't be slow"
        },
        timeWarning = {
            "ur running out of time",
            "the point isn't gonna cap itself",
            "last window and ur still not there",
            "clock's not ur friend rn"
        },
        nearWin = {
            "gg",
            "u played well, just not well enough",
            "almost done with u",
            "gg, better luck next time"
        },
        nearLose = {
            "good play, noted",
            "u caught me, won't happen twice",
            "didn't think u had that in u",
            "earned that one"
        },
        obj_win = {
            "that point's mine now",
            "ur resource line is cut off",
            "locked it down"
        },
        obj_lose = {
            "u won't hold that long",
            "enjoy the point, i'm already flanking",
            "fine, i'll take it back"
        }
    },

    ["bot_spectre"] = {
        start = {
            "boots on the ground, come on then",
            "first wave's down, let's see what ur made of",
            "weapons hot, ur move",
            "deployed and hunting u down"
        },
        timeWarning = {
            "one minute left and ur still losing",
            "stop waiting and PUSH",
            "time's almost gone and ur nowhere near the point",
            "last chance, u gonna do something or not"
        },
        nearWin = {
            "ur almost done",
            "finish it, ur finished",
            "it's over for u",
            "u fought well but it's done"
        },
        nearLose = {
            "didn't think u had that push in u",
            "ur lines hit harder than i expected",
            "u got me on the ropes, won't stay there",
            "good hit, i'm still coming"
        },
        obj_win = {
            "that objective's ours now, push ur luck",
            "ur point is mine, come take it back",
            "we own that sector, try and stop us"
        },
        obj_lose = {
            "u got the point but can u hold it",
            "ur on it, won't be for long",
            "fine, i'll hit u from the flank"
        }
    },

    ["bot_tryhard"] = {
        start = {
            "ez game already i can tell",
            "bro ur cooked and u don't even know it yet",
            "i do this for fun and u still can't beat me lmao",
            "warming up on u rn no cap"
        },
        timeWarning = {
            "stop stalling u can't win just accept it",
            "ur literally not gonna make it in time",
            "PUSH already or just forfeit one of the two",
            "times running out and ur still bad lol"
        },
        nearWin = {
            "told u from the start",
            "too easy honestly, next",
            "this was literally warmup for me",
            "u never had a chance bro and u knew it"
        },
        nearLose = {
            "server is genuinely unplayable rn",
            "would've won easy with decent ping",
            "u got lucky, run it back?",
            "ok that was actually a bug no way that counts"
        },
        obj_win = {
            "obviously i took it",
            "wasn't even a contest",
            "that's mine now, bye"
        },
        obj_lose = {
            "i'll have that back in 30 seconds watch",
            "i was letting u cap that one relax",
            "doesn't even matter"
        }
    },

    ["bot_runner"] = {
        start = {
            "blink and you'll miss me",
            "good luck catching me lol",
            "i'm already ahead of u",
            "ur already behind and u don't know it"
        },
        timeWarning = {
            "u gotta move WAY faster than that",
            "ur running out of time and u still can't catch up",
            "i'm all over the map and ur stuck",
            "u literally cannot keep up with me"
        },
        nearWin = {
            "gg, couldn't keep up could u",
            "too slow, speed wins every time",
            "i was gone before u even reacted lmao",
            "blink and u lost"
        },
        nearLose = {
            "ok ok u actually kept pace with me",
            "respect, didn't think u could match that",
            "alright ur actually good i'll give u that",
            "u kept up, not many people do that"
        },
        obj_win = {
            "already capped it, were u even watching",
            "in and out before u even noticed",
            "point's mine, too slow"
        },
        obj_lose = {
            "fine u got that, i'll be back for it",
            "ur on it but i'm already routing around u",
            "enjoy it for like 30 seconds"
        }
    },

    ["bot_glitch"] = {
        start = {
            "lagging in... wait no i'm good gl",
            "connection's stable for now, glhf",
            "hope ur server holds better than mine lol",
            "loading in, probably, gl out there"
        },
        timeWarning = {
            "times running and i'm lagging but still beating u somehow",
            "clock going, rubber banding my units onto ur point",
            "almost out of time and i'm still here on 200 ping",
            "last minute, teleporting my troops to u rn"
        },
        nearWin = {
            "gg, latency and all",
            "beat u on 200 ping lmao",
            "gg ez (on my end at least)",
            "won despite everything, that's on u"
        },
        nearLose = {
            "this is 100% a desync issue not ur skill",
            "i was winning on my screen i swear",
            "server literally said no to me",
            "packet loss cost me that not u"
        },
        obj_win = {
            "somehow capped it through the lag",
            "point's mine, secured it between packet drops",
            "teleported onto ur objective lol"
        },
        obj_lose = {
            "rubber banded off the point smh",
            "i capped it on my screen it counted trust",
            "packet loss gave u that one not skill"
        }
    },

    ["default"] = {
        start = {
            "gl hf",
            "let's go, ur move",
            "first platoon's down",
            "game on, don't be slow"
        },
        timeWarning = {
            "one minute, get on the point",
            "ur running out of time",
            "make ur move now",
            "clock's going and ur still losing"
        },
        nearWin = {
            "almost done with u",
            "gg incoming",
            "ur nearly done",
            "u fought well, nearly over"
        },
        nearLose = {
            "ur better than i expected",
            "good push, i'm still here though",
            "didn't see that coming",
            "good game so far, not done yet"
        },
        obj_win = {
            "that point's mine, good luck",
            "resources secured, ur losing ground",
            "got the objective, come take it back"
        },
        obj_lose = {
            "u got the point, won't hold it",
            "ur on it, i'm flanking",
            "fine, i'm coming for it"
        }
    }
}