extends RefCounted
## The one datagram budget for every Ironwood RPC.
##
## Godot's ENetMultiplayerPeer exposes no MTU setting (`create_server` takes
## only port, clients, channels and bandwidth), and ENet fragments anything
## above its own fixed MTU. Fragmentation is the failure this file prevents: a
## fragmented unreliable snapshot dies whole when one fragment is lost, so the
## payload budget is applied on our side of the socket.
##
## `MTU` is 1200 bytes: below IPv6's 1280-byte minimum link MTU and below the
## roughly 1400-byte payload ENet itself fragments at, so a whole snapshot fits
## one datagram on ordinary internet paths. `ENVELOPE` covers the RPC
## method/peer/packet header plus the ENet header that wrap these arguments.

## Hard ceiling for one datagram. Nothing may encode past this.
const MTU := 1200
## Allowance on top of the encoded arguments for the RPC header (method name,
## peer and packet ids) plus the ENet header.
const ENVELOPE := 100
## Budget for the encoded argument list itself.
const PAYLOAD := MTU - ENVELOPE
## A Godot array encodes as this header plus each element's own bytes.
const ARRAY_HEADER := 8

static func size(value: Variant) -> int:
	return var_to_bytes(value).size()

## Encoded size of one RPC's argument list, the same encoder the RPC sends.
static func message_size(args: Array) -> int:
	var total := ARRAY_HEADER
	for arg in args:
		total += size(arg)
	return total

static func fits(args: Array) -> bool:
	return message_size(args) <= PAYLOAD

## Splits `entries` into array arguments that each fit `PAYLOAD` once `fixed`
## (the snapshot tick) rides beside them. `batches([])` is empty. An entry too
## big to share a datagram is still returned alone rather than dropped, so a
## regression can catch the oversized snapshot instead of hiding it.
static func batches(entries: Array, fixed: Array = []) -> Array:
	var base := message_size(fixed) + ARRAY_HEADER
	var out: Array = []
	var batch: Array = []
	var used := base
	for entry in entries:
		var cost := size(entry)
		if not batch.is_empty() and used + cost > PAYLOAD:
			out.append(batch)
			batch = []
			used = base
		batch.append(entry)
		used += cost
	if not batch.is_empty():
		out.append(batch)
	return out
