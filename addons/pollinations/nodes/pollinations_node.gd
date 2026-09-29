class_name PollinationsNode
extends Node

## Shared plumbing for every Pollinations node: one client per node, unless a
## project wants to share a single client (and its retry policy) by pointing
## `client_path` at it.

## Optional shared PollinationsClient. When empty the node creates and owns one.
@export var client_path: NodePath

## Print request and retry details to the console.
@export var debug: bool = false

## The client in use. Created on first request.
var client: PollinationsClient = null

## Returns the client for this node, creating one if needed.
func ensure_client() -> PollinationsClient:
	if client != null and is_instance_valid(client):
		return client
	if not client_path.is_empty():
		var found := get_node_or_null(client_path)
		if found is PollinationsClient:
			client = found
			client.debug = debug or client.debug
			return client
		push_warning("[pollinations] client_path %s is not a PollinationsClient" % client_path)
	var existing := get_node_or_null("PollinationsClient")
	if existing is PollinationsClient:
		client = existing
		return client
	client = PollinationsClient.new()
	client.name = "PollinationsClient"
	client.debug = debug
	add_child(client)
	return client
