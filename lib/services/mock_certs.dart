import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

import 'storage.dart';

const _oidSha256Rsa = '1.2.840.113549.1.1.11';
const _oidRsa = '1.2.840.113549.1.1.1';
const _oidCn = '2.5.4.3';
const _oidBasic = '2.5.29.19';
const _oidKeyUsage = '2.5.29.15';
const _oidExtKeyUsage = '2.5.29.37';
const _oidSan = '2.5.29.17';
const _oidServerAuth = '1.3.6.1.5.5.7.3.1';
const _oidSki = '2.5.29.14';
const _oidAki = '2.5.29.35';

const String _caCommonName = 'Astra Local Traffic CA';
const String _caFileName = 'mock-ca.json';

class _KeyMaterial {
  final RSAPublicKey pub;
  final RSAPrivateKey priv;
  _KeyMaterial(this.pub, this.priv);
}

_KeyMaterial _generateKey(int bits) {
  final random = FortunaRandom();
  final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  random.seed(KeyParameter(Uint8List.fromList(seed)));
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
      random,
    ));
  final pair = generator.generateKeyPair();
  return _KeyMaterial(
    pair.publicKey as RSAPublicKey,
    pair.privateKey as RSAPrivateKey,
  );
}

ASN1Sequence _algorithmId(String oid) => ASN1Sequence()
  ..add(ASN1ObjectIdentifier.fromComponentString(oid))
  ..add(ASN1Null());

ASN1Sequence _name(String commonName) => ASN1Sequence()
  ..add(ASN1Set()
    ..add(ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromComponentString(_oidCn))
      ..add(ASN1UTF8String(commonName))));

Uint8List _skiOf(RSAPublicKey key) {
  final rsaKey = ASN1Sequence()
    ..add(ASN1Integer(key.modulus!))
    ..add(ASN1Integer(key.publicExponent!));
  return SHA1Digest().process(rsaKey.encodedBytes);
}

ASN1Sequence _extension(String oid, List<int> value, {bool critical = false}) {
  final sequence = ASN1Sequence()..add(ASN1ObjectIdentifier.fromComponentString(oid));
  if (critical) sequence.add(ASN1Boolean(true));
  sequence.add(ASN1OctetString(value));
  return sequence;
}

Uint8List _subjectAltName(String host) {
  final asIp = InternetAddress.tryParse(host);
  final generalName = asIp != null
      ? ASN1Object.preEncoded(0x87, Uint8List.fromList(asIp.rawAddress))
      : ASN1Object.preEncoded(0x82, Uint8List.fromList(utf8.encode(host)));
  return (ASN1Sequence()..add(generalName)).encodedBytes;
}

Uint8List _buildCertificate({
  required _KeyMaterial subject,
  required String subjectCn,
  required _KeyMaterial issuer,
  required String issuerCn,
  required BigInt serial,
  required bool isCa,
  String? dnsName,
  DateTime? notBefore,
  DateTime? notAfter,
}) {
  final start = notBefore ?? DateTime.now().toUtc().subtract(const Duration(days: 1));
  final end = notAfter ?? DateTime.now().toUtc().add(const Duration(days: 365));
  final extensions = ASN1Sequence();
  extensions.add(_extension(_oidSki, ASN1OctetString(_skiOf(subject.pub)).encodedBytes));
  extensions.add(_extension(
    _oidAki,
    (ASN1Sequence()..add(ASN1Object.preEncoded(0x80, _skiOf(issuer.pub)))).encodedBytes,
  ));
  if (isCa) {
    extensions.add(_extension(
      _oidBasic,
      (ASN1Sequence()..add(ASN1Boolean(true))).encodedBytes,
      critical: true,
    ));
    extensions.add(_extension(
      _oidKeyUsage,
      ASN1BitString([0x86], unusedbits: 1).encodedBytes,
      critical: true,
    ));
  } else {
    extensions.add(_extension(
      _oidBasic,
      (ASN1Sequence()..add(ASN1Boolean(false))).encodedBytes,
      critical: true,
    ));
    extensions.add(_extension(
      _oidKeyUsage,
      ASN1BitString([0x80], unusedbits: 7).encodedBytes,
      critical: true,
    ));
    extensions.add(_extension(
      _oidExtKeyUsage,
      (ASN1Sequence()..add(ASN1ObjectIdentifier.fromComponentString(_oidServerAuth)))
          .encodedBytes,
    ));
    if (dnsName != null && dnsName.isNotEmpty) {
      extensions.add(_extension(_oidSan, _subjectAltName(dnsName)));
    }
  }

  final rsaKey = ASN1Sequence()
    ..add(ASN1Integer(subject.pub.modulus!))
    ..add(ASN1Integer(subject.pub.publicExponent!));
  final tbs = ASN1Sequence()
    ..add(ASN1Sequence(tag: 0xA0)..add(ASN1Integer(BigInt.two)))
    ..add(ASN1Integer(serial))
    ..add(_algorithmId(_oidSha256Rsa))
    ..add(_name(issuerCn))
    ..add(ASN1Sequence()
      ..add(ASN1UtcTime(start))
      ..add(ASN1UtcTime(end)))
    ..add(_name(subjectCn))
    ..add(ASN1Sequence()
      ..add(_algorithmId(_oidRsa))
      ..add(ASN1BitString(rsaKey.encodedBytes.toList())))
    ..add(ASN1Sequence(tag: 0xA3)..add(extensions));

  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(issuer.priv));
  final signature = signer.generateSignature(tbs.encodedBytes);
  return (ASN1Sequence()
        ..add(ASN1Object.fromBytes(tbs.encodedBytes))
        ..add(_algorithmId(_oidSha256Rsa))
        ..add(ASN1BitString(signature.bytes.toList())))
      .encodedBytes;
}

Uint8List _privateKeyDer(RSAPrivateKey key) {
  final dP = key.privateExponent! % (key.p! - BigInt.one);
  final dQ = key.privateExponent! % (key.q! - BigInt.one);
  final qInv = key.q!.modInverse(key.p!);
  return (ASN1Sequence()
        ..add(ASN1Integer(BigInt.zero))
        ..add(ASN1Integer(key.modulus!))
        ..add(ASN1Integer(key.publicExponent ?? BigInt.from(65537)))
        ..add(ASN1Integer(key.privateExponent!))
        ..add(ASN1Integer(key.p!))
        ..add(ASN1Integer(key.q!))
        ..add(ASN1Integer(dP))
        ..add(ASN1Integer(dQ))
        ..add(ASN1Integer(qInv)))
      .encodedBytes;
}

String _pem(List<int> der, String label) {
  final body = base64.encode(der);
  final buffer = StringBuffer('-----BEGIN $label-----\n');
  for (var i = 0; i < body.length; i += 64) {
    buffer.writeln(body.substring(i, min(i + 64, body.length)));
  }
  buffer.write('-----END $label-----\n');
  return buffer.toString();
}

String _hex(BigInt value) => value.toRadixString(16);

BigInt _fromHex(String value) => BigInt.parse(value, radix: 16);

/// 本地抓包代理使用的根证书。
///
/// 首次启动时生成并保存到应用数据目录；之后为每个主机用同一份私钥签发
/// 一张叶证书。私钥只保存在本地，导出给用户的只有 CA 证书。
class CertificateAuthority {
  CertificateAuthority._(
    this._storage,
    this._caKey,
    this._leafKey,
    this.caDer,
    this.createdAt,
  );

  final Storage _storage;
  final _KeyMaterial _caKey;
  final _KeyMaterial _leafKey;
  final Uint8List caDer;
  final DateTime createdAt;
  final Map<String, SecurityContext> _contexts = {};
  int _serial = 0;

  String get caPem => _pem(caDer, 'CERTIFICATE');
  String get commonName => _caCommonName;
  DateTime get expiresAt => DateTime(createdAt.year + 10, createdAt.month, createdAt.day);

  /// 读取已有 CA，不存在时生成一份（首条约 0.3 秒）。
  static Future<CertificateAuthority> loadOrCreate(Storage storage) async {
    final stored = await storage.read(_caFileName);
    if (stored != null) {
      try {
        final ca = _restore(storage, stored);
        if (ca != null) return ca;
      } catch (_) {
        // 数据损坏时重新生成，避免代理无法启动
      }
    }
    final caKey = _generateKey(2048);
    final leafKey = _generateKey(2048);
    final now = DateTime.now().toUtc();
    final der = _buildCertificate(
      subject: caKey,
      subjectCn: _caCommonName,
      issuer: caKey,
      issuerCn: _caCommonName,
      serial: BigInt.one,
      isCa: true,
      notBefore: now.subtract(const Duration(days: 1)),
      notAfter: now.add(const Duration(days: 3650)),
    );
    await storage.write(_caFileName, {
      'cert': base64.encode(der),
      'createdAt': now.toIso8601String(),
      'ca': _encodeKey(caKey),
      'leaf': _encodeKey(leafKey),
    });
    return CertificateAuthority._(storage, caKey, leafKey, der, now);
  }

  static CertificateAuthority? _restore(Storage storage, Map<String, dynamic> data) {
    final cert = base64.decode('${data['cert'] ?? ''}');
    final caKey = _decodeKey(data['ca']);
    final leafKey = _decodeKey(data['leaf']);
    if (cert.isEmpty || caKey == null || leafKey == null) return null;
    final createdAt = DateTime.tryParse('${data['createdAt'] ?? ''}') ?? DateTime.now();
    return CertificateAuthority._(storage, caKey, leafKey, cert, createdAt);
  }

  static Map<String, dynamic> _encodeKey(_KeyMaterial key) => {
        'n': _hex(key.priv.modulus!),
        'e': _hex(key.priv.publicExponent ?? BigInt.from(65537)),
        'd': _hex(key.priv.privateExponent!),
        'p': _hex(key.priv.p!),
        'q': _hex(key.priv.q!),
      };

  static _KeyMaterial? _decodeKey(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final n = _fromHex('${raw['n']}');
      final e = _fromHex('${raw['e']}');
      final d = _fromHex('${raw['d']}');
      final p = _fromHex('${raw['p']}');
      final q = _fromHex('${raw['q']}');
      final priv = RSAPrivateKey(n, d, p, q, e);
      return _KeyMaterial(RSAPublicKey(n, e), priv);
    } catch (_) {
      return null;
    }
  }

  /// 为指定主机签发（并缓存）TLS 证书上下文。
  SecurityContext serverContextFor(String host) {
    final cached = _contexts[host];
    if (cached != null) return cached;
    _serial += 1;
    final leafDer = _buildCertificate(
      subject: _leafKey,
      subjectCn: host,
      issuer: _caKey,
      issuerCn: _caCommonName,
      serial: BigInt.from(DateTime.now().microsecondsSinceEpoch + _serial),
      isCa: false,
      dnsName: host,
    );
    final context = SecurityContext()
      ..useCertificateChainBytes(
        utf8.encode('${_pem(leafDer, 'CERTIFICATE')}$caPem'),
      )
      ..usePrivateKeyBytes(utf8.encode(_pem(_privateKeyDer(_leafKey.priv), 'RSA PRIVATE KEY')));
    if (_contexts.length > 128) _contexts.clear();
    _contexts[host] = context;
    return context;
  }

  /// 供测试使用：只信任该 CA 的客户端上下文。
  SecurityContext trustedClientContext() => SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(caPem));

  /// 把 CA 证书写入应用数据目录，返回文件路径。
  Future<String> exportCaCertificate() async {
    final directory = await _storage.directory();
    final file = File('${directory.path}${Platform.pathSeparator}astra-ca.pem');
    await file.writeAsString(caPem, flush: true);
    return file.path;
  }
}
