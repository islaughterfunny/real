/obj/structure/bed/chair/wheelchair
	name = "wheelchair"
	desc = "Now we're getting somewhere."
	icon_state = "wheelchair"
	anchored = FALSE
	movement_handlers = list(/datum/movement_handler/deny_multiz, /datum/movement_handler/delay = list(5), /datum/movement_handler/move_relay_self)
	var/driving = 0
	var/mob/living/pulling = null
	var/bloodiness

/obj/structure/bed/chair/wheelchair/on_update_icon()
	return

/obj/structure/bed/chair/wheelchair/setDir()
	..()
	cut_overlays()
	var/image/O = image(icon = 'icons/obj/furniture.dmi', icon_state = "w_overlay", dir = src.dir)
	O.layer = ABOVE_HUMAN_LAYER
	add_overlay(O)
	if(buckled_mob)
		buckled_mob.setDir(dir)

/obj/structure/bed/chair/wheelchair/attackby(obj/item/W as obj, mob/user as mob)
	if(isWrench(W) || istype(W,/obj/item/stack) || isWirecutter(W))
		return
	..()

/obj/structure/bed/chair/wheelchair/relaymove(mob/user, direction)
	// Redundant check?
	if(user.stat || user.stunned || user.weakened || user.paralysis || user.lying || user.restrained())
		if(user==pulling)
			pulling = null
			user.pulledby = null
			to_chat(user, SPAN_WARNING("You lost your grip!"))
		return
	if(buckled_mob && pulling && user == buckled_mob)
		if(pulling.stat || pulling.stunned || pulling.weakened || pulling.paralysis || pulling.lying || pulling.restrained())
			pulling.pulledby = null
			pulling = null
	if(user.pulling && (user == pulling))
		pulling = null
		user.pulledby = null
		return
	if(propelled)
		return
	if(pulling && (get_dist(src, pulling) > 1))
		pulling = null
		user.pulledby = null
		if(user==pulling)
			return
	if(pulling && (get_dir(src.loc, pulling.loc) == direction))
		to_chat(user, SPAN_WARNING("You cannot go there."))
		return
	if(pulling && buckled_mob && (buckled_mob == user))
		to_chat(user, SPAN_WARNING("You cannot drive while being pushed."))
		return

	// Let's roll
	driving = 1
	var/turf/T = null
	//--1---Move occupant---1--//
	if(buckled_mob)
		buckled_mob.buckled = null
		step(buckled_mob, direction)
		buckled_mob.buckled = src
	//--2----Move driver----2--//
	if(pulling)
		T = pulling.loc
		if(get_dist(src, pulling) >= 1)
			step(pulling, get_dir(pulling.loc, src.loc))
	//--3--Move wheelchair--3--//
	step(src, direction)
	if(buckled_mob) // Make sure it stays beneath the occupant
		Move(buckled_mob.loc)
	setDir(direction)
	if(pulling) // Driver
		if(pulling.loc == src.loc) // We moved onto the wheelchair? Revert!
			pulling.forceMove(T)
		else
			spawn(0)
			if(get_dist(src, pulling) > 1) // We are too far away? Losing control.
				pulling = null
				user.pulledby = null
			pulling.setDir(get_dir(pulling, src)) // When everything is right, face the wheelchair
	if(bloodiness)
		create_track()
	driving = 0

/obj/structure/bed/chair/wheelchair/Move()
	. = ..()
	if(buckled_mob)
		var/mob/living/occupant = buckled_mob
		if(!driving)
			if (occupant && (src.loc != occupant.loc))
				if (propelled)
					for (var/mob/O in src.loc)
						if (O != occupant)
							Bump(O)
				else
					unbuckle_mob()
			if (pulling && (get_dist(src, pulling) > 1))
				pulling.pulledby = null
				to_chat(pulling, SPAN_WARNING("You lost your grip!"))
				pulling = null
		else
			if (occupant && (src.loc != occupant.loc))
				src.forceMove(occupant.loc) // Failsafe to make sure the wheelchair stays beneath the occupant after driving

/obj/structure/bed/chair/wheelchair/attack_hand(mob/living/user as mob)
	if (pulling)
		MouseDrop(usr)
	else
		user_unbuckle_mob(user)
	return

/obj/structure/bed/chair/wheelchair/CtrlClick(mob/user)
	if(in_range(src, user))
		if(!ishuman(user))	return
		if(user == buckled_mob)
			to_chat(user, SPAN_WARNING("You realize you are unable to push the wheelchair you sit in."))
			return
		if(!pulling)
			pulling = user
			user.pulledby = src
			if(user.pulling)
				user.stop_pulling()
			user.setDir(get_dir(user, src))
			to_chat(user, "You grip \the [name]'s handles.")
		else
			to_chat(usr, "You let go of \the [name]'s handles.")
			pulling.pulledby = null
			pulling = null
		return TRUE
	return FALSE

/obj/structure/bed/chair/wheelchair/Bump(atom/A)
	..()
	if(!buckled_mob)	return

	if(propelled || (pulling && (pulling.a_intent == I_HURT)))
		var/mob/living/occupant = unbuckle_mob()

		if (pulling && (pulling.a_intent == I_HURT))
			occupant.throw_at(A, 3, 3, pulling)
		else if (propelled)
			occupant.throw_at(A, 3, 3)

		var/def_zone = ran_zone()
		var/blocked = 100 * occupant.get_blocked_ratio(def_zone, BRUTE, damage = 10)
		occupant.throw_at(A, 3, 3)
		occupant.apply_effect(6, STUN, blocked)
		occupant.apply_effect(6, WEAKEN, blocked)
		occupant.adjust_stutter(6 SECONDS * ((100 - blocked) / 100))
		occupant.apply_damage(10, BRUTE, def_zone)
		playsound(src.loc, 'sounds/weapons/punch1.ogg', 50, 1, -1)
		if(istype(A, /mob/living))
			var/mob/living/victim = A
			def_zone = ran_zone()
			blocked = 100 * victim.get_blocked_ratio(def_zone, BRUTE, damage = 10)
			victim.apply_effect(6, STUN, blocked)
			victim.apply_effect(6, WEAKEN, blocked)
			victim.adjust_stutter(6 SECONDS * ((100 - blocked) / 100))
			victim.apply_damage(10, BRUTE, def_zone)
		if(pulling)
			occupant.visible_message(SPAN_DANGER("[pulling] has thrusted \the [name] into \the [A], throwing \the [occupant] out of it!"))
			admin_attack_log(pulling, occupant, "Crashed their victim into \an [A].", "Was crashed into \an [A].", "smashed into \the [A] using")
		else
			occupant.visible_message(SPAN_DANGER("[occupant] crashed into \the [A]!"))

/obj/structure/bed/chair/wheelchair/proc/create_track()
	var/obj/effect/decal/cleanable/blood/tracks/B = new(loc)
	var/newdir = get_dir(get_step(loc, dir), loc)
	if(newdir == dir)
		B.setDir(newdir)
	else
		newdir = newdir | dir
		if(newdir == 3)
			newdir = 1
		else if(newdir == 12)
			newdir = 4
		B.setDir(newdir)
	bloodiness--

/obj/structure/bed/chair/wheelchair/buckle_mob(mob/M as mob, mob/user as mob)
	if(M == pulling)
		pulling = null
		usr.pulledby = null
	..()

/proc/equip_wheelchair(mob/living/carbon/human/H) //Proc for spawning in a wheelchair if a new character has no legs. Used in new_player.dm
	var/obj/structure/bed/chair/wheelchair/W = new(get_turf(H))
	if(isturf(H.loc))
		W.buckle_mob(H)
