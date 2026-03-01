import 'package:flutter/material.dart';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({
    super.key,
    required this.title,
    required this.apiKeyLabel,
    required this.mcpUrlLabel,
    required this.mcpTokenLabel,
    required this.debugLogsLabel,
    required this.debugLogsDescription,
    required this.initialDebugLogsEnabled,
    required this.securityNotice,
    required this.clearLabel,
    required this.saveLabel,
    required this.apiKeyController,
    required this.mcpUrlController,
    required this.mcpBearerTokenController,
    required this.onClear,
    required this.onSave,
  });

  final String title;
  final String apiKeyLabel;
  final String mcpUrlLabel;
  final String mcpTokenLabel;
  final String debugLogsLabel;
  final String debugLogsDescription;
  final bool initialDebugLogsEnabled;
  final String securityNotice;
  final String clearLabel;
  final String saveLabel;
  final TextEditingController apiKeyController;
  final TextEditingController mcpUrlController;
  final TextEditingController mcpBearerTokenController;
  final Future<void> Function() onClear;
  final Future<void> Function(bool debugLogsEnabled) onSave;

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  bool _obscureApiKey = true;
  bool _obscureMcpBearerToken = true;
  late bool _debugLogsEnabled;

  @override
  void initState() {
    super.initState();
    _debugLogsEnabled = widget.initialDebugLogsEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: widget.apiKeyLabel,
              hintText: 'AIza...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscureApiKey = !_obscureApiKey;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.mcpUrlController,
            decoration: InputDecoration(
              labelText: widget.mcpUrlLabel,
              hintText: 'https://your-mcp-server.example.com/mcp',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.mcpBearerTokenController,
            obscureText: _obscureMcpBearerToken,
            decoration: InputDecoration(
              labelText: widget.mcpTokenLabel,
              hintText: 'eyJ...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureMcpBearerToken
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscureMcpBearerToken = !_obscureMcpBearerToken;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.debugLogsLabel),
            subtitle: Text(widget.debugLogsDescription),
            value: _debugLogsEnabled,
            onChanged: (bool value) {
              setState(() {
                _debugLogsEnabled = value;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(widget.securityNotice, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onClear();
                },
                child: Text(widget.clearLabel),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onSave(_debugLogsEnabled);
                },
                child: Text(widget.saveLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
