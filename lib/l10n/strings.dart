import 'package:flutter/widgets.dart';

class AppStrings {
  AppStrings(this.locale);
  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('ja'), Locale('zh')];

  static const _values = <String, Map<String, String>>{
    'en': {
      'title': 'TTS Text to MP3',
      'file': 'TXT / EPUB file',
      'choose': 'Choose file',
      'provider': 'Provider',
      'credentials': 'Credentials',
      'apiKey': 'API key',
      'region': 'Region',
      'persist': 'Store securely on this device',
      'forget': 'Delete saved credentials',
      'split': 'Split method',
      'chapter': 'By chapter',
      'chars': 'By character count',
      'maxChars': 'Maximum characters',
      'voice': 'Voice',
      'loadVoices': 'Load voices',
      'preview': 'Preview (~15 sec)',
      'generate': 'Generate MP3',
      'noFile': 'Choose a TXT or EPUB file first.',
      'unsupported': 'Not supported on mobile',
      'limitations':
          'OpenAI and Google service-account JSON are not supported. See the mobile README for security reasons.',
      'done': 'MP3 files generated.',
    },
    'ja': {
      'title': 'TTS Text to MP3',
      'file': 'TXT / EPUBファイル',
      'choose': 'ファイルを選択',
      'provider': 'プロバイダ',
      'credentials': '認証情報',
      'apiKey': 'APIキー',
      'region': 'リージョン',
      'persist': 'この端末へ安全に保存する',
      'forget': '保存した認証情報を削除',
      'split': '分割方法',
      'chapter': '章ごと',
      'chars': '文字数ごと',
      'maxChars': '最大文字数',
      'voice': '音声',
      'loadVoices': '音声一覧を取得',
      'preview': '音声確認（約15秒）',
      'generate': 'MP3を生成',
      'noFile': '先にTXTまたはEPUBファイルを選択してください。',
      'unsupported': 'モバイル版の非対応機能',
      'limitations':
          'OpenAIとGoogleサービスアカウントJSONには対応していません。安全上の理由はmobile READMEをご覧ください。',
      'done': 'MP3ファイルを生成しました。',
    },
    'zh': {
      'title': 'TTS Text to MP3',
      'file': 'TXT / EPUB文件',
      'choose': '选择文件',
      'provider': '提供商',
      'credentials': '凭据',
      'apiKey': 'API密钥',
      'region': '区域',
      'persist': '安全地保存在此设备上',
      'forget': '删除已保存的凭据',
      'split': '拆分方式',
      'chapter': '按章节',
      'chars': '按字符数',
      'maxChars': '最大字符数',
      'voice': '语音',
      'loadVoices': '加载语音',
      'preview': '试听（约15秒）',
      'generate': '生成MP3',
      'noFile': '请先选择TXT或EPUB文件。',
      'unsupported': '移动版不支持的功能',
      'limitations': '不支持OpenAI和Google服务账号JSON。安全原因请参阅mobile README。',
      'done': 'MP3文件已生成。',
    },
  };

  String get(String key) =>
      _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;
}
