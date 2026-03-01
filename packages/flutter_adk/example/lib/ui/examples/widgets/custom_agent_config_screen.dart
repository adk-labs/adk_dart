import 'package:flutter/material.dart';

import 'package:flutter_adk_example/domain/models/custom_agent_config.dart';

class CustomAgentConfigScreen extends StatefulWidget {
  const CustomAgentConfigScreen({
    super.key,
    required this.title,
    required this.nameLabel,
    required this.descriptionLabel,
    required this.instructionLabel,
    required this.capitalToolLabel,
    required this.weatherToolLabel,
    required this.timeToolLabel,
    required this.cancelLabel,
    required this.saveLabel,
    required this.initialConfig,
  });

  final String title;
  final String nameLabel;
  final String descriptionLabel;
  final String instructionLabel;
  final String capitalToolLabel;
  final String weatherToolLabel;
  final String timeToolLabel;
  final String cancelLabel;
  final String saveLabel;
  final CustomAgentConfig initialConfig;

  @override
  State<CustomAgentConfigScreen> createState() =>
      _CustomAgentConfigScreenState();
}

class _CustomAgentConfigScreenState extends State<CustomAgentConfigScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _instructionController;

  late bool _enableCapitalTool;
  late bool _enableWeatherTool;
  late bool _enableTimeTool;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialConfig.name);
    _descriptionController = TextEditingController(
      text: widget.initialConfig.description,
    );
    _instructionController = TextEditingController(
      text: widget.initialConfig.instruction,
    );
    _enableCapitalTool = widget.initialConfig.enableCapitalTool;
    _enableWeatherTool = widget.initialConfig.enableWeatherTool;
    _enableTimeTool = widget.initialConfig.enableTimeTool;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  void _save() {
    final CustomAgentConfig base = widget.initialConfig;
    final CustomAgentConfig next = base.copyWith(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      instruction: _instructionController.text.trim(),
      enableCapitalTool: _enableCapitalTool,
      enableWeatherTool: _enableWeatherTool,
      enableTimeTool: _enableTimeTool,
    );
    Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.nameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: widget.descriptionLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instructionController,
              minLines: 6,
              maxLines: 14,
              decoration: InputDecoration(
                labelText: widget.instructionLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.capitalToolLabel),
              value: _enableCapitalTool,
              onChanged: (bool value) {
                setState(() {
                  _enableCapitalTool = value;
                });
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.weatherToolLabel),
              value: _enableWeatherTool,
              onChanged: (bool value) {
                setState(() {
                  _enableWeatherTool = value;
                });
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.timeToolLabel),
              value: _enableTimeTool,
              onChanged: (bool value) {
                setState(() {
                  _enableTimeTool = value;
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(widget.cancelLabel),
                ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(widget.saveLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
