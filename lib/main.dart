// =====================================================================
// ZEN MOTOS - ORÇAMENTO RÁPIDO
// App Flutter para orçamentos rápidos de oficina mecânica de motos.
// Consome Firestore (clientes / pecas), gera PDF padronizado e
// formata mensagem para envio via WhatsApp.
// =====================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------
// CORES DO TEMA
// -----------------------------------------------------------------------
class ZenColors {
  static const Color background = Color(0xFF121212);
  static const Color card = Color(0xFF1E1E1E);
  static const Color blue = Color(0xFF0F4C81);
  static const Color whatsapp = Color(0xFF25D366);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB0B0B0);
}

// -----------------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZenMotosApp());
}

class ZenMotosApp extends StatelessWidget {
  const ZenMotosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zen Motos - Orçamento Rápido',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ZenColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ZenColors.blue,
          brightness: Brightness.dark,
          surface: ZenColors.card,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: ZenColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ZenColors.blue, width: 1.6),
          ),
          labelStyle: const TextStyle(color: ZenColors.textSecondary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      home: const OrcamentoPage(),
    );
  }
}

// -----------------------------------------------------------------------
// MODELO DE ITEM DO ORÇAMENTO
// -----------------------------------------------------------------------
class OrcamentoItem {
  final String descricao;
  final double quantidade;
  final double valorUnitario;

  OrcamentoItem({
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
  });

  double get valorTotal => quantidade * valorUnitario;
}

// -----------------------------------------------------------------------
// TELA PRINCIPAL
// -----------------------------------------------------------------------
class OrcamentoPage extends StatefulWidget {
  const OrcamentoPage({super.key});

  @override
  State<OrcamentoPage> createState() => _OrcamentoPageState();
}

class _OrcamentoPageState extends State<OrcamentoPage> {
  // Controllers
  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _cpfCnpjController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _veiculoController = TextEditingController();
  final TextEditingController _pecaController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _qtdController =
      TextEditingController(text: '1');

  final List<OrcamentoItem> _itens = [];

  final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<String> _clientesSalvos = [];
  List<Map<String, dynamic>> _pecasSalvas = [];

  @override
  void initState() {
    super.initState();
    _carregarDadosLocais();
  }

  // ---------------------------------------------------------------------
  // CARREGAR CLIENTES/PEÇAS SALVOS NO APARELHO
  // ---------------------------------------------------------------------
  Future<void> _carregarDadosLocais() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientesJson = prefs.getString('zm_clientes');
      final pecasJson = prefs.getString('zm_pecas');
      final clientes = clientesJson != null
          ? List<String>.from(jsonDecode(clientesJson) as List)
          : <String>[];
      final pecas = pecasJson != null
          ? (jsonDecode(pecasJson) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _clientesSalvos = clientes;
          _pecasSalvas = pecas;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados locais: $e');
    }
  }

  // ---------------------------------------------------------------------
  // BUSCA DE CLIENTES SALVOS NO APARELHO (autocompletar + digitação livre)
  // ---------------------------------------------------------------------
  Future<List<String>> _buscarClientes(String pattern) async {
    if (pattern.trim().isEmpty) return [];
    final termo = pattern.toLowerCase();
    final resultado = _clientesSalvos
        .where((nome) => nome.toLowerCase().contains(termo))
        .toList();
    resultado.sort();
    return resultado;
  }

  // ---------------------------------------------------------------------
  // BUSCA DE PEÇAS/SERVIÇOS SALVOS NO APARELHO (autocompletar + digitação livre)
  // ---------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _buscarPecas(String pattern) async {
    if (pattern.trim().isEmpty) return [];
    final termo = pattern.toLowerCase();
    final resultado = _pecasSalvas
        .where((peca) =>
            (peca['descricao'] as String).toLowerCase().contains(termo))
        .toList();
    resultado.sort((a, b) =>
        (a['descricao'] as String).compareTo(b['descricao'] as String));
    return resultado;
  }

  // ---------------------------------------------------------------------
  // SALVAR CLIENTE / PEÇA NO APARELHO (pra aparecer no autocompletar depois)
  // ---------------------------------------------------------------------
  Future<void> _salvarClienteLocal(String nome) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.isEmpty) return;
    final jaExiste = _clientesSalvos
        .any((c) => c.toLowerCase() == nomeLimpo.toLowerCase());
    if (jaExiste) return;
    _clientesSalvos.add(nomeLimpo);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zm_clientes', jsonEncode(_clientesSalvos));
    } catch (e) {
      debugPrint('Erro ao salvar cliente: $e');
    }
  }

  Future<void> _salvarPecaLocal(String descricao, double preco) async {
    final descLimpa = descricao.trim();
    if (descLimpa.isEmpty) return;
    final index = _pecasSalvas.indexWhere((p) =>
        (p['descricao'] as String).toLowerCase() == descLimpa.toLowerCase());
    if (index >= 0) {
      _pecasSalvas[index]['preco_padrao'] = preco;
    } else {
      _pecasSalvas.add({'descricao': descLimpa, 'preco_padrao': preco});
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zm_pecas', jsonEncode(_pecasSalvas));
    } catch (e) {
      debugPrint('Erro ao salvar peça: $e');
    }
  }

  // ---------------------------------------------------------------------
  // ADICIONAR ITEM AO ORÇAMENTO
  // ---------------------------------------------------------------------
  void _incluirItem() {
    final descricao = _pecaController.text.trim();
    final valorTexto =
        _valorController.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final qtdTexto = _qtdController.text.trim().replaceAll(',', '.');

    if (descricao.isEmpty) {
      _mostrarErro('Informe a peça ou serviço.');
      return;
    }

    final valor = double.tryParse(valorTexto);
    if (valor == null || valor <= 0) {
      _mostrarErro('Informe um valor unitário válido.');
      return;
    }

    final qtd = double.tryParse(qtdTexto) ?? 1;
    if (qtd <= 0) {
      _mostrarErro('Informe uma quantidade válida.');
      return;
    }

    setState(() {
      _itens.add(OrcamentoItem(
        descricao: descricao,
        quantidade: qtd,
        valorUnitario: valor,
      ));
      _pecaController.clear();
      _valorController.clear();
      _qtdController.text = '1';
    });

    // Salva cliente e peça no aparelho, pra aparecerem no autocompletar
    // da próxima vez (não trava a tela esperando).
    _salvarPecaLocal(descricao, valor);
    if (_clienteController.text.trim().isNotEmpty) {
      _salvarClienteLocal(_clienteController.text);
    }
  }

  void _removerItem(int index) {
    setState(() => _itens.removeAt(index));
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  double get _totalGeral =>
      _itens.fold(0.0, (soma, item) => soma + item.valorTotal);

  String get _nomeCliente {
    final nome = _clienteController.text.trim();
    return nome.isEmpty ? 'NÃO INFORMADO' : nome;
  }

  String get _cpfCnpjCliente {
    final valor = _cpfCnpjController.text.trim();
    return valor.isEmpty ? 'NÃO INFORMADO' : valor;
  }

  String get _telefoneCliente {
    final valor = _telefoneController.text.trim();
    return valor.isEmpty ? 'NÃO INFORMADO' : valor;
  }

  String get _veiculoCliente {
    final valor = _veiculoController.text.trim();
    return valor.isEmpty ? 'NÃO INFORMADO' : valor;
  }

  // ---------------------------------------------------------------------
  // NÚMERO SEQUENCIAL DO ORÇAMENTO (salvo no aparelho, tipo 0001, 0002...)
  // ---------------------------------------------------------------------
  Future<String> _proximoNumeroOrcamento() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final atual = prefs.getInt('zm_contador_orcamento') ?? 0;
      final proximo = atual + 1;
      await prefs.setInt('zm_contador_orcamento', proximo);
      return proximo.toString().padLeft(4, '0');
    } catch (e) {
      debugPrint('Erro ao gerar número do orçamento: $e');
      return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    }
  }

  // ---------------------------------------------------------------------
  // HISTÓRICO DE ORÇAMENTOS (salvo no aparelho)
  // ---------------------------------------------------------------------
  Future<void> _salvarNoHistorico(String numero) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('zm_historico');
      final historico = json != null
          ? List<Map<String, dynamic>>.from(
              (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];
      historico.insert(0, {
        'numero': numero,
        'data': DateTime.now().toIso8601String(),
        'cliente': _nomeCliente,
        'veiculo': _veiculoCliente,
        'total': _totalGeral,
        'itens': _itens
            .map((i) => {
                  'descricao': i.descricao,
                  'quantidade': i.quantidade,
                  'valorUnitario': i.valorUnitario,
                })
            .toList(),
      });
      await prefs.setString('zm_historico', jsonEncode(historico));
    } catch (e) {
      debugPrint('Erro ao salvar histórico: $e');
    }
  }

  void _abrirHistorico() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoricoPage()),
    );
  }

  void _confirmarNovoOrcamento() {
    if (_clienteController.text.trim().isEmpty && _itens.isEmpty) {
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ZenColors.card,
        title: const Text('Novo orçamento?',
            style: TextStyle(color: ZenColors.textPrimary)),
        content: const Text(
          'Isso limpa o cliente e os itens da tela atual. O histórico não é apagado.',
          style: TextStyle(color: ZenColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _limparOrcamento();
            },
            child:
                const Text('Limpar', style: TextStyle(color: ZenColors.whatsapp)),
          ),
        ],
      ),
    );
  }

  void _limparOrcamento() {
    setState(() {
      _clienteController.clear();
      _cpfCnpjController.clear();
      _telefoneController.clear();
      _veiculoController.clear();
      _itens.clear();
    });
  }

  // ---------------------------------------------------------------------
  // MONTA O TEXTO PARA WHATSAPP / BLOCO DE NOTAS
  // ---------------------------------------------------------------------
  String _montarTextoWhatsApp() {
    final buffer = StringBuffer();
    buffer.writeln('Olá! 🛠️ Aqui é da Zen Motos.');
    buffer.writeln();
    buffer.writeln('Segue seu orçamento:');
    buffer.writeln();

    for (final item in _itens) {
      final qtd = _formatarQtd(item.quantidade);
      buffer.writeln(
          'CLIENTE: $_nomeCliente | ${qtd}x ${item.descricao} | R\$ ${_valorFmt(item.valorTotal)}');
    }

    buffer.writeln();
    buffer.writeln('TOTAL: R\$ ${_valorFmt(_totalGeral)}');
    buffer.writeln();
    buffer.write('Qualquer dúvida estou à disposição! 🔧');

    return buffer.toString();
  }

  String _formatarQtd(double qtd) {
    if (qtd == qtd.roundToDouble()) {
      return qtd.toInt().toString();
    }
    return qtd.toString();
  }

  String _valorFmt(double valor) {
    return NumberFormat('#,##0.00', 'pt_BR').format(valor);
  }

  // ---------------------------------------------------------------------
  // AÇÃO: COPIAR / COMPARTILHAR WHATSAPP
  // ---------------------------------------------------------------------
  Future<void> _copiarWhatsApp() async {
    if (_itens.isEmpty) {
      _mostrarErro('Inclua ao menos um item no orçamento.');
      return;
    }

    final texto = _montarTextoWhatsApp();

    await Clipboard.setData(ClipboardData(text: texto));

    final numero = await _proximoNumeroOrcamento();
    await _salvarNoHistorico(numero);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orçamento copiado! Abrindo compartilhamento...'),
          backgroundColor: ZenColors.whatsapp,
        ),
      );
    }

    await Share.share(texto, subject: 'Orçamento Zen Motos');
  }

  // ---------------------------------------------------------------------
  // AÇÃO: GERAR PDF
  // ---------------------------------------------------------------------
  Future<void> _gerarPdf() async {
    if (_itens.isEmpty) {
      _mostrarErro('Inclua ao menos um item no orçamento.');
      return;
    }

    final agora = DateTime.now();
    final nomeArquivo = 'OS_${DateFormat('dd_MM_yyyy').format(agora)}.pdf';
    final numeroOrcamento = await _proximoNumeroOrcamento();

    final bytes = await _construirPdf(numeroOrcamento);

    await _salvarNoHistorico(numeroOrcamento);

    await Printing.sharePdf(bytes: bytes, filename: nomeArquivo);
  }

  Future<Uint8List> _construirPdf(String numeroOrcamento) async {
    final doc = pw.Document();
    final azulMarca = PdfColor.fromHex('#0F4C81');
    final verdeAccent = PdfColor.fromHex('#1E8E4F');

    final veiculo = _veiculoCliente;
    final cpfCnpj = _cpfCnpjCliente;
    final telefoneCliente = _telefoneCliente;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'ZEN MOTOS',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: azulMarca,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Av. Pereira da Rosa, 104 - Caminho Novo, Palhoça - SC, 88130-000',
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.Text(
              'CNPJ: 65.037.425/0001-10',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Telefone: (48) 98441-8911',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Facebook: Zen Motos | Instagram: zen_motos',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: azulMarca, thickness: 1),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey400, thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Text(
              'Orçamento válido por 15 dias. Peças e serviços com garantia legal de 90 dias.',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            pw.Text(
              'Obrigado pela preferência!',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'ORÇAMENTO N° $numeroOrcamento',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 14),

          // Caixa com dados do cliente e do veículo
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey600, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DADOS DO CLIENTE',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text('Nome: $_nomeCliente',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('CPF/CNPJ: $cpfCnpj',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Telefone: $telefoneCliente',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 8),
                pw.Text(
                  'DADOS DO VEÍCULO',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text('Veículo: $veiculo',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          // Tabela principal de itens
          pw.TableHelper.fromTextArray(
            headers: ['ITEM', 'DESCRIÇÃO', 'QTD', 'VALOR UNIT.', 'TOTAL'],
            data: List<List<String>>.generate(_itens.length, (i) {
              final item = _itens[i];
              return [
                (i + 1).toString(),
                item.descricao,
                _formatarQtd(item.quantidade),
                'R\$ ${_valorFmt(item.valorUnitario)}',
                'R\$ ${_valorFmt(item.valorTotal)}',
              ];
            }),
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: azulMarca),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.6),
              1: const pw.FlexColumnWidth(3.2),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FlexColumnWidth(1.4),
            },
          ),

          pw.SizedBox(height: 14),

          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: verdeAccent,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'TOTAL GERAL: R\$ ${_valorFmt(_totalGeral)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // =======================================================================
  // UI
  // =======================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildClienteField(),
                    const SizedBox(height: 20),
                    _buildAdicionarItensBloco(),
                    const SizedBox(height: 20),
                    _buildCorpoOrcamento(),
                  ],
                ),
              ),
            ),
            _buildBotoesAcao(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: ZenColors.card,
        border: Border(
          bottom: BorderSide(color: ZenColors.blue, width: 2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ZEN MOTOS',
                  style: TextStyle(
                    color: ZenColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ZenColors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '⚡ ORÇAMENTO RÁPIDO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history, color: ZenColors.textPrimary),
            tooltip: 'Histórico de orçamentos',
            onPressed: _abrirHistorico,
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined,
                color: ZenColors.textPrimary),
            tooltip: 'Novo orçamento',
            onPressed: _confirmarNovoOrcamento,
          ),
        ],
      ),
    );
  }

  Widget _buildClienteField() {
    return _sectionCard(
      title: 'CLIENTE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      TypeAheadField<String>(
        controller: _clienteController,
        builder: (context, controller, focusNode) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: ZenColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Digite ou selecione o cliente',
              hintStyle: TextStyle(color: ZenColors.textSecondary),
              prefixIcon: Icon(Icons.person, color: ZenColors.textSecondary),
            ),
          );
        },
        suggestionsCallback: _buscarClientes,
        itemBuilder: (context, suggestion) {
          return ListTile(
            tileColor: ZenColors.card,
            title: Text(suggestion,
                style: const TextStyle(color: ZenColors.textPrimary)),
          );
        },
        onSelected: (suggestion) {
          _clienteController.text = suggestion;
        },
        emptyBuilder: (context) => const SizedBox.shrink(),
        decorationBuilder: (context, child) => Material(
          type: MaterialType.card,
          color: ZenColors.card,
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: child,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cpfCnpjController,
              style: const TextStyle(color: ZenColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'CPF/CNPJ (opcional)',
                prefixIcon:
                    Icon(Icons.badge_outlined, color: ZenColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _telefoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: ZenColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Telefone (opcional)',
                prefixIcon:
                    Icon(Icons.phone_outlined, color: ZenColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _veiculoController,
        style: const TextStyle(color: ZenColors.textPrimary),
        decoration: const InputDecoration(
          labelText: 'Veículo (opcional) — ex: GSX 650F 2010',
          prefixIcon:
              Icon(Icons.two_wheeler_outlined, color: ZenColors.textSecondary),
        ),
      ),
        ],
      ),
    );
  }

  Widget _buildAdicionarItensBloco() {
    return _sectionCard(
      title: 'ADICIONAR ITENS',
      child: Column(
        children: [
          TypeAheadField<Map<String, dynamic>>(
            controller: _pecaController,
            builder: (context, controller, focusNode) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: ZenColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Peça ou serviço',
                  hintStyle: TextStyle(color: ZenColors.textSecondary),
                  prefixIcon:
                      Icon(Icons.build, color: ZenColors.textSecondary),
                ),
              );
            },
            suggestionsCallback: _buscarPecas,
            itemBuilder: (context, suggestion) {
              final preco = suggestion['preco_padrao'] as double;
              return ListTile(
                tileColor: ZenColors.card,
                title: Text(
                  suggestion['descricao'] as String,
                  style: const TextStyle(color: ZenColors.textPrimary),
                ),
                trailing: Text(
                  _moeda.format(preco),
                  style: const TextStyle(color: ZenColors.textSecondary),
                ),
              );
            },
            onSelected: (suggestion) {
              _pecaController.text = suggestion['descricao'] as String;
              final preco = suggestion['preco_padrao'] as double;
              _valorController.text = preco.toStringAsFixed(2);
            },
            emptyBuilder: (context) => const SizedBox.shrink(),
            decorationBuilder: (context, child) => Material(
              type: MaterialType.card,
              color: ZenColors.card,
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              child: child,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _valorController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: ZenColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Valor unit. (R\$)',
                    prefixIcon:
                        Icon(Icons.attach_money, color: ZenColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qtdController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: ZenColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Qtd',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _incluirItem,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                '+ INCLUIR NO ORÇAMENTO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZenColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorpoOrcamento() {
    return _sectionCard(
      title: 'CORPO DO ORÇAMENTO (EDITÁVEL)',
      child: Column(
        children: [
          if (_itens.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nenhum item incluído ainda.',
                style: TextStyle(color: ZenColors.textSecondary),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _itens.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Colors.white12, height: 1),
              itemBuilder: (context, index) {
                final item = _itens[index];
                final qtd = _formatarQtd(item.quantidade);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CLIENTE: $_nomeCliente | ${qtd}x ${item.descricao} | R\$ ${_valorFmt(item.valorTotal)}',
                          style: const TextStyle(
                            color: ZenColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent, size: 20),
                        onPressed: () => _removerItem(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (_itens.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL GERAL',
                  style: TextStyle(
                    color: ZenColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'R\$ ${_valorFmt(_totalGeral)}',
                  style: const TextStyle(
                    color: ZenColors.whatsapp,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBotoesAcao() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: ZenColors.card,
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _gerarPdf,
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text(
                'GERAR PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZenColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _copiarWhatsApp,
              icon: const Icon(Icons.share, color: Colors.white),
              label: const Text(
                'COPIAR WHATSAPP',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZenColors.whatsapp,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZenColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ZenColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _cpfCnpjController.dispose();
    _telefoneController.dispose();
    _veiculoController.dispose();
    _pecaController.dispose();
    _valorController.dispose();
    _qtdController.dispose();
    super.dispose();
  }
}

// -----------------------------------------------------------------------
// TELA DE HISTÓRICO DE ORÇAMENTOS (salvos no aparelho)
// -----------------------------------------------------------------------
class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  List<Map<String, dynamic>> _historico = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('zm_historico');
      final lista = json != null
          ? List<Map<String, dynamic>>.from((jsonDecode(json) as List)
              .map((e) => Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _historico = lista;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _formatarData(String iso) {
    try {
      final data = DateTime.parse(iso);
      return DateFormat('dd/MM/yyyy HH:mm').format(data);
    } catch (_) {
      return iso;
    }
  }

  String _valorFmt(double valor) {
    return NumberFormat('#,##0.00', 'pt_BR').format(valor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZenColors.background,
      appBar: AppBar(
        backgroundColor: ZenColors.card,
        foregroundColor: ZenColors.textPrimary,
        title: const Text('Histórico de Orçamentos'),
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: ZenColors.blue),
            )
          : _historico.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum orçamento gerado ainda.',
                    style: TextStyle(color: ZenColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historico.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = _historico[index];
                    final itens = (item['itens'] as List)
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    final total = (item['total'] as num).toDouble();
                    return Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: ZenColors.card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ExpansionTile(
                          collapsedIconColor: ZenColors.textSecondary,
                          iconColor: ZenColors.whatsapp,
                          title: Text(
                            'Orçamento #${item['numero']} — ${item['cliente']}',
                            style: const TextStyle(
                              color: ZenColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${_formatarData(item['data'] as String)} • R\$ ${_valorFmt(total)}',
                            style:
                                const TextStyle(color: ZenColors.textSecondary),
                          ),
                          children: itens.map((i) {
                            final qtd = (i['quantidade'] as num).toDouble();
                            final valorUnit =
                                (i['valorUnitario'] as num).toDouble();
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${qtd == qtd.roundToDouble() ? qtd.toInt() : qtd}x ${i['descricao']}',
                                      style: const TextStyle(
                                          color: ZenColors.textPrimary),
                                    ),
                                  ),
                                  Text(
                                    'R\$ ${_valorFmt(valorUnit * qtd)}',
                                    style: const TextStyle(
                                        color: ZenColors.textSecondary),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
