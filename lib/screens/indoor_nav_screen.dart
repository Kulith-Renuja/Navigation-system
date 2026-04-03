import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/semantics.dart';
import '../models/indoor_graph.dart';

class IndoorNavScreen extends StatefulWidget {
  const IndoorNavScreen({super.key});

  @override
  State<IndoorNavScreen> createState() => _IndoorNavScreenState();
}

class _IndoorNavScreenState extends State<IndoorNavScreen> {
  IndoorGraph? _graph;
  bool _isLoading = true;
  String _errorMessage = '';

  MapNode? _startNode;
  MapNode? _destNode;

  @override
  void initState() {
    super.initState();
    _fetchMapData();
  }

  Future<void> _fetchMapData() async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('maps')
          .doc('ueue')
          .collection('mrnr')
          .doc('ekkek')
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        setState(() {
          _graph = IndoorGraph.fromJson(docSnapshot.data()!);
          _isLoading = false;
        });
        if (mounted) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Map loaded',
            TextDirection.ltr,
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Map data not found.';
        });
        if (mounted) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Map data not found.',
            TextDirection.ltr,
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading map: $e';
      });
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Error loading map',
          TextDirection.ltr,
        );
      }
      debugPrint("Fetch error: $e");
    }
  }

  void _calculateRoute() {
    if (_startNode != null && _destNode != null) {
      debugPrint("Calculate Route Pressed.");
      debugPrint("Start Node: ${_startNode!.name} (ID: ${_startNode!.id})");
      debugPrint("Destination Node: ${_destNode!.name} (ID: ${_destNode!.id})");
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Calculating route from ${_startNode!.name} to ${_destNode!.name}',
        TextDirection.ltr,
      );
    } else {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Please select both start and destination nodes',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic screen: Omitted `const` on Scaffold intentionally to obey constraints.
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Semantics(
          header: true,
          child: const Text(
            'Indoor Navigation',
            style: TextStyle(
              color: Colors.yellowAccent,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.yellowAccent),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Semantics(
          label: 'Loading map data, please wait',
          child: const CircularProgressIndicator(
            color: Colors.yellowAccent,
            strokeWidth: 8.0,
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Semantics(
          label: _errorMessage,
          child: Text(
            _errorMessage,
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_graph == null || _graph!.nodes.isEmpty) {
      return Center(
        child: Semantics(
          label: 'Map has no nodes available.',
          child: const Text(
            'No Nodes Found',
            style: TextStyle(
              color: Colors.yellowAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Location: ${_graph!.locationName} - ${_graph!.buildingName} Floor ${_graph!.floorName}',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 48),

          Semantics(
            label: 'Where are you starting? Dropdown menu.',
            hint: 'Double tap to select your current location',
            child: _buildLargeDropdown(
              value: _startNode,
              hint: 'Where are you starting?',
              onChanged: (MapNode? newValue) {
                setState(() {
                  _startNode = newValue;
                });
                if (newValue != null) {
                  SemanticsService.sendAnnouncement(
                    View.of(context),
                    'Start location set to ${newValue.name}',
                    TextDirection.ltr,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 32),

          Semantics(
            label: 'Where do you want to go? Dropdown menu.',
            hint: 'Double tap to select your destination',
            child: _buildLargeDropdown(
              value: _destNode,
              hint: 'Where do you want to go?',
              onChanged: (MapNode? newValue) {
                setState(() {
                  _destNode = newValue;
                });
                if (newValue != null) {
                  SemanticsService.sendAnnouncement(
                    View.of(context),
                    'Destination set to ${newValue.name}',
                    TextDirection.ltr,
                  );
                }
              },
            ),
          ),

          const Spacer(),

          Semantics(
            button: true,
            label: 'Calculate Route Button',
            hint: 'Double tap to calculate the route between selected nodes',
            child: ElevatedButton(
              onPressed: (_startNode != null && _destNode != null)
                  ? _calculateRoute
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellowAccent,
                disabledBackgroundColor: Colors.yellowAccent.withValues(
                  alpha: 0.5,
                ),
                padding: const EdgeInsets.symmetric(vertical: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Calculate Route',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildLargeDropdown({
    required MapNode? value,
    required String hint,
    required ValueChanged<MapNode?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.yellowAccent, width: 4),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MapNode>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          icon: const Icon(
            Icons.arrow_drop_down,
            color: Colors.yellowAccent,
            size: 48,
          ),
          dropdownColor: Colors.black,
          isExpanded: true,
          style: const TextStyle(
            color: Colors.yellowAccent,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
          items: _graph!.nodes.map((MapNode node) {
            return DropdownMenuItem<MapNode>(
              value: node,
              child: Text(node.name),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
