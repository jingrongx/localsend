import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/debug/debug_page.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.aboutPage.title),
      ),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        children: [
          const SizedBox(height: 20),
          const LocalSendLogo(withText: true),
          Text(
            t.aboutPage.description.join('\n\n'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse('https://github.com/jingrongx/localsend'), mode: LaunchMode.externalApplication);
                },
                child: const Text('GitHub'),
              ),
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse('https://github.com/localsend/localsend'), mode: LaunchMode.externalApplication);
                },
                child: Text(t.aboutPage.upstreamProject),
              ),
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'));
                },
                child: const Text('Apache License 2.0'),
              ),
              TextButton(
                onPressed: () async {
                  await context.push(() => const LicensePage());
                },
                child: Text(t.aboutPage.licenseNotices),
              ),
              TextButton(
                onPressed: () async {
                  await context.push(() => const DebugPage());
                },
                child: Text(t.aboutPage.debugging),
              ),
            ],
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}
