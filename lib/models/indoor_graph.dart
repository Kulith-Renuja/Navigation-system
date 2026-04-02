class MapNode {
  final String id;
  final String name;
  final double x;
  final double y;

  MapNode({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
  });

  factory MapNode.fromJson(Map<String, dynamic> json) {
    return MapNode(
      id: json['id'] as String,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'x': x,
      'y': y,
    };
  }
}

class MapEdge {
  final String fromNodeId;
  final String toNodeId;
  final String direction; // "forward", "backward", "left", "right"
  final int stepCount;

  MapEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.direction,
    required this.stepCount,
  });

  factory MapEdge.fromJson(Map<String, dynamic> json) {
    return MapEdge(
      fromNodeId: json['fromNodeId'] as String,
      toNodeId: json['toNodeId'] as String,
      direction: json['direction'] as String,
      stepCount: json['stepCount'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
      'direction': direction,
      'stepCount': stepCount,
    };
  }
}

class IndoorGraph {
  final String locationName;
  final String buildingName;
  final String floorName;
  final List<MapNode> nodes;
  final List<MapEdge> edges;

  IndoorGraph({
    required this.locationName,
    required this.buildingName,
    required this.floorName,
    required this.nodes,
    required this.edges,
  });

  factory IndoorGraph.fromJson(Map<String, dynamic> json) {
    var nodesList = json['nodes'] as List? ?? [];
    var edgesList = json['edges'] as List? ?? [];

    return IndoorGraph(
      locationName: json['locationName'] as String,
      buildingName: json['buildingName'] as String,
      floorName: json['floorName'] as String,
      nodes: nodesList.map((n) => MapNode.fromJson(n as Map<String, dynamic>)).toList(),
      edges: edgesList.map((e) => MapEdge.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'locationName': locationName,
      'buildingName': buildingName,
      'floorName': floorName,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
  }
}
