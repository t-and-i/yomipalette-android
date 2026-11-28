import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/review_access.dart';

class ReviewAccessScreen extends StatefulWidget {
  const ReviewAccessScreen({required this.controller, super.key});
  final ReviewAccessController controller;

  @override
  State<ReviewAccessScreen> createState() => _ReviewAccessScreenState();
}

class _ReviewAccessScreenState extends State<ReviewAccessScreen> {
  final _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(Localizations.localeOf(context));
    final review = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(s.get('reviewEntry'))),
      body: ListenableBuilder(
        listenable: review,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (review.isActive) Text(s.get('reviewActive')),
            if (review.hasCredential && !review.isActive)
              Text(s.get('reviewReconnect')),
            Text(s.get('reviewInstructions')),
            const SizedBox(height: 16),
            if (!review.hasCredential) ...[
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(labelText: s.get('reviewToken')),
                enabled: !review.busy,
              ),
              FilledButton(
                onPressed: review.busy || !review.configured
                    ? null
                    : () async {
                        final token = _token.text;
                        _token.clear();
                        FocusScope.of(context).unfocus();
                        await review.register(token);
                      },
                child: Text(s.get('reviewActivate')),
              ),
            ] else ...[
              OutlinedButton(
                onPressed: review.busy
                    ? null
                    : () => review.refresh(force: true),
                child: Text(s.get('reviewRefresh')),
              ),
              TextButton(
                onPressed: review.busy ? null : review.endAccess,
                child: Text(s.get('reviewEnd')),
              ),
            ],
            if (!review.configured) Text(s.get('reviewUnavailable')),
            if (review.busy) const LinearProgressIndicator(),
            if (review.message != null) Text(s.get(review.message!)),
          ],
        ),
      ),
    );
  }
}
