unit UGerenciadorDePastasPrincipal;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, System.IOUtils, System.Types,
  Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls, UClasseValidacao, TFormConfiguracaoGerenciador, Clipbrd, ShellAPI, System.UITypes, RichEdit, UFeedBack,
  Vcl.ComCtrls, Vcl.Menus, StrUtils;

procedure VerificarRepositoriosGit(const Caminho: string);


type
  TFGerenciadorDePastas = class(TForm)
    btIniciar: TBitBtn;
    btSair: TBitBtn;
    Panel1: TPanel;
    Panel2: TPanel;
    ComboBoxBranch: TComboBox;
    Label1: TLabel;
    BtCopiarLog: TBitBtn;
    BtAbrirLog: TBitBtn;
    MemoLogNaTela: TRichEdit;
    MainMenuAjuda: TMainMenu;
    Menu1: TMenuItem;
    Configuracao: TMenuItem;
    GuiaDeUso: TMenuItem;
    N2: TMenuItem;
    Reportdebug: TMenuItem;
    Label2: TLabel;
    ComboBoxSubPastas: TComboBox;
    ProgressBarCarregamento: TProgressBar;
    procedure Logs();
    procedure FormCreate(Sender: TObject);
    procedure btSairClick(Sender: TObject);
    procedure btIniciarClick(Sender: TObject);
    procedure MemoLogNaTela1Change(Sender: TObject);
    procedure BtCopiarLogClick(Sender: TObject);
    procedure BtAbrirLogClick(Sender: TObject);
    procedure ConfiguracaoClick(Sender: TObject);
    procedure GuiaDeUsoClick(Sender: TObject);
    procedure ReportdebugClick(Sender: TObject);
    procedure PreencherComboBoxSubPastas;
    procedure CarregamentoProgress;
    procedure ComboBoxSubPastasChange(Sender: TObject);
    procedure FormShow(Sender: TObject);

  private
    { Private declarations }
  public
     procedure AdicionarLogNaTela(const Msg: string);
    { Public declarations }
  end;

var
  HouveErro: Boolean;
  FGerenciadorDePastas: TFGerenciadorDePastas;
  ListaDeRepositoriosGit: TStringList;
  SSHAuthSock: string;
  Executar: function(const Comando, Pasta: string): string;


implementation

{$R *.dfm}

procedure TFGerenciadorDePastas.BtAbrirLogClick(Sender: TObject);
begin
  if (ArquivoLogGlobal <> '') and FileExists(ArquivoLogGlobal) then
  begin
    ShellExecute(0, 'open', PChar(ArquivoLogGlobal), nil, nil, SW_SHOWNORMAL);
  end
  else
  begin
    MessageDlg('Arquivo de log não encontrado.', mtWarning, [mbOK], 0);
  end;
end;

procedure TFGerenciadorDePastas.BtCopiarLogClick(Sender: TObject);
begin
  Clipboard.AsText := MemoLogNaTela.Text;
end;

procedure TFGerenciadorDePastas.CarregamentoProgress;
begin
  ProgressBarCarregamento.Min := 0;
  ProgressBarCarregamento.Max := 100;

  if ProgressBarCarregamento.Position + 10 <= ProgressBarCarregamento.Max then
    ProgressBarCarregamento.Position := ProgressBarCarregamento.Position + 25
  else
    ProgressBarCarregamento.Position := ProgressBarCarregamento.Max;
end;

function ComandoFalhou(const Resultado: string): Boolean;
begin
  Result := (CodigoSaidaUltimoGit <> 0) or
    (Pos('fatal', LowerCase(Resultado)) > 0) or
    (Pos('error', LowerCase(Resultado)) > 0) or
    (Pos('conflict', LowerCase(Resultado)) > 0);
end;

procedure TFGerenciadorDePastas.btIniciarClick(Sender: TObject);
var
  BranchSelecionada, PastaSelecionada, PastaRepo, Resultado: string;
  BranchLocal, BranchRemota, NomeRemoto, NomeBranchRemota: string;
  BranchLocalExiste: Boolean;
  Separador: Integer;
  Repositorios: TStringList;
  I: Integer;
begin
  BranchSelecionada := Trim(ComboBoxBranch.Text);
  PastaSelecionada := ComboBoxSubPastas.Text;

  if BranchSelecionada = '' then
  begin
    ShowMessage('Selecione uma branch local ou remota antes de iniciar.');
    Exit;
  end;

  Repositorios := TStringList.Create;
  try
    if PastaSelecionada = '--- Todas as sub pastas ---' then
      Repositorios.Assign(ListaDeRepositoriosGit)
    else
      for I := 0 to ListaDeRepositoriosGit.Count - 1 do
        if SameText(ExtractFileName(ListaDeRepositoriosGit[I]), PastaSelecionada) then
        begin
          Repositorios.Add(ListaDeRepositoriosGit[I]);
          Break;
        end;

    if Repositorios.Count = 0 then
    begin
      ShowMessage('Nenhum repositorio Git valido foi encontrado para a selecao.');
      Exit;
    end;

    btIniciar.Enabled := False;
    ComboBoxBranch.Enabled := False;
    ComboBoxSubPastas.Enabled := False;
    MemoLogNaTela.Clear;
    ProgressBarCarregamento.Position := 0;
    HouveErro := False;
    Executar := ExecutarComandoGit;

    AdicionarLogNaTela('Branch selecionada: ' + BranchSelecionada);
    AdicionarLogNaTela('A operacao usa somente checkout e pull --ff-only.');

    for I := 0 to Repositorios.Count - 1 do
    begin
      PastaRepo := Repositorios[I];
      AdicionarLogNaTela('Processando: ' + PastaRepo);

      if ArquivoLogGlobal <> '' then
        TFile.AppendAllText(ArquivoLogGlobal,
          Format('Processando repositorio: %s | branch: %s%s',
            [PastaRepo, BranchSelecionada, sLineBreak]), TEncoding.UTF8);

      BranchLocal := BranchSelecionada;
      BranchRemota := '';
      NomeRemoto := '';
      NomeBranchRemota := '';
      BranchLocalExiste := False;
      if StartsText('remotes/', BranchSelecionada) then
      begin
        BranchRemota := Copy(BranchSelecionada, Length('remotes/') + 1, MaxInt);
        Separador := Pos('/', BranchRemota);
        if Separador = 0 then
        begin
          AdicionarLogNaTela('Referencia remota invalida; repositorio ignorado: ' + BranchSelecionada);
          HouveErro := True;
          CarregamentoProgress;
          Continue;
        end;
        NomeRemoto := Copy(BranchRemota, 1, Separador - 1);
        NomeBranchRemota := Copy(BranchRemota, Separador + 1, MaxInt);
        BranchLocal := NomeBranchRemota;
      end;

      if BranchRemota <> '' then
      begin
        if not BranchRemotaExiste(PastaRepo, BranchRemota, Executar) then
        begin
          AdicionarLogNaTela('Branch remota ausente; repositorio ignorado: ' + PastaRepo);
          HouveErro := True;
          CarregamentoProgress;
          Continue;
        end;
        BranchLocalExiste := BranchExiste(PastaRepo, BranchLocal, Executar);
        if BranchLocalExiste then
          AdicionarLogNaTela('Branch local existente sera atualizada pela referencia remota selecionada: ' + BranchRemota)
        else
          AdicionarLogNaTela('Branch local inexistente; sera criada a partir de: ' + BranchRemota);
      end
      else if not BranchExiste(PastaRepo, BranchLocal, Executar) then
      begin
        AdicionarLogNaTela('Branch local ausente; repositorio ignorado: ' + PastaRepo);
        HouveErro := True;
        CarregamentoProgress;
        Continue;
      end;
      if HaAlteracoesPendentes(PastaRepo, Executar) then
      begin
        AdicionarLogNaTela('Alteracoes locais ou erro de status; repositorio ignorado: ' + PastaRepo);
        HouveErro := True;
        CarregamentoProgress;
        Continue;
      end;

      if BranchAtual(PastaRepo, Executar) <> BranchLocal then
      begin
        if (BranchRemota <> '') and not BranchLocalExiste then
          Resultado := Executar('checkout --track -b ' + BranchLocal + ' ' + BranchRemota, PastaRepo)
        else
          Resultado := Executar('checkout ' + BranchLocal, PastaRepo);
        if ComandoFalhou(Resultado) then
        begin
          AdicionarLogNaTela('Checkout falhou; pull nao executado: ' + Trim(Resultado));
          HouveErro := True;
          CarregamentoProgress;
          Continue;
        end;
      end
      else
        AdicionarLogNaTela('Branch ja estava selecionada.');

      if BranchRemota <> '' then
        Resultado := Executar('pull --ff-only ' + NomeRemoto + ' ' + NomeBranchRemota, PastaRepo)
      else
        Resultado := Executar('pull --ff-only', PastaRepo);
      if ComandoFalhou(Resultado) then
      begin
        AdicionarLogNaTela('Pull falhou: ' + Trim(Resultado));
        HouveErro := True;
      end
      else
        AdicionarLogNaTela('Checkout/pull concluido em: ' + PastaRepo);

      CarregamentoProgress;
    end;

    if HouveErro then
      AdicionarLogNaTela('Processo concluido com repositorios ignorados ou erros.')
    else
      AdicionarLogNaTela('Processo concluido com sucesso.');
  finally
    btIniciar.Enabled := True;
    ComboBoxBranch.Enabled := True;
    ComboBoxSubPastas.Enabled := True;
    Repositorios.Free;
  end;
end;

procedure TFGerenciadorDePastas.btSairClick(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TFGerenciadorDePastas.ComboBoxSubPastasChange(Sender: TObject);
var
  SubpastaSelecionada: string;
  Repositorios: TStringList;
  ListaBranches: TStringList;
  I: Integer;
  CaminhoCompleto: string;
begin
  ComboBoxBranch.Items.Clear;
  btIniciar.Enabled := False;
  Repositorios := TStringList.Create;
  ListaBranches := TStringList.Create;
  try
    SubpastaSelecionada := ComboBoxSubPastas.Text;
    TFile.AppendAllText(ArquivoLogGlobal, 'Sub Pasta selecionada' + sLineBreak);
    if SubpastaSelecionada = '--- Todas as sub pastas ---' then
    begin
      Repositorios.Assign(ListaDeRepositoriosGit);
    end
    else
    begin
      // Busca o caminho completo correspondente ao nome da subpasta selecionada
      for I := 0 to ListaDeRepositoriosGit.Count - 1 do
      begin
        CaminhoCompleto := ListaDeRepositoriosGit[I];
        if ExtractFileName(CaminhoCompleto) = SubpastaSelecionada then
        begin
          Repositorios.Add(CaminhoCompleto);
          Break;
        end;
      end;
    end;
    CaminhoGit := LerCaminhoGitDoINI();
    // Chama o método que obtém e ordena os branches
    ObterBranchesUnicas(CaminhoGit, Repositorios, ListaBranches);
    btIniciar.Enabled := true;

    ComboBoxBranch.Items.AddStrings(ListaBranches);

  finally
    Repositorios.Free;
    ListaBranches.Free;
  end;
end;

procedure TFGerenciadorDePastas.ConfiguracaoClick(Sender: TObject);
var
  CaminhoGit: string;
begin
  if not NovaConfiguracaoGit then
    Exit; // o usuário cancelou a configuração


  CaminhoGit := LerCaminhoGitDoINI;
  if Trim(CaminhoGit) = '' then
  begin
    ShowMessage('Caminho do Git não configurado. Vá em configurações e defina o caminho correto.');
    Exit;
  end;

  if not DirectoryExists(CaminhoGit) then
  begin
    ShowMessage('O caminho do Git informado no arquivo de configuração não existe mais.');
    Exit;
  end;

  // Recarrega a autenticacao salva e solicita ao Pageant carregar a PPK sem
  // exigir que o usuario reinicie o aplicativo.
  ValidarConfiguracaoGit;
end;

procedure TFGerenciadorDePastas.PreencherComboBoxSubPastas;
var
  RepoPath: string;
begin
  ComboBoxSubPastas.Items.Clear;
  ComboBoxSubPastas.Items.Add('--- Todas as sub pastas ---');

  for RepoPath in ListaDeRepositoriosGit do
    ComboBoxSubPastas.Items.Add(ExtractFileName(RepoPath)); // pega apenas o nome da subpasta

  ComboBoxSubPastas.ItemIndex := 0;
end;

procedure TFGerenciadorDePastas.FormCreate(Sender: TObject);
var
  DataHoje, CaminhoDebug, ArquivoLogAtual, CaminhoGit, CaminhoProjetos: string;
  InfoArq: TSearchRec;
begin
  btIniciar.Enabled:=false;
  OnLogMensagem := AdicionarLogNaTela;
  ValidarConfiguracaoGit;
  CaminhoDebug := GetEnvironmentVariable('GERENCIADOR_DEBUG');
  if CaminhoDebug <> '' then
    CaminhoProjetos := CaminhoDebug
  else
    CaminhoProjetos := ParamStr(1);


  if not TDirectory.Exists(CaminhoProjetos) then
  begin
    ShowMessage('Pasta de instalação não encontrada: ' + CaminhoProjetos);
    Exit;
  end;
  Logs;

  VerificarRepositoriosGit(CaminhoProjetos);
  PreencherComboBoxSubPastas;

  CaminhoGit := LerCaminhoGitDoINI;
  MemoLogNaTela.Clear;
  MemoLogNaTela.ScrollBars := ssBoth ;
  MemoLogNaTela.WordWrap := False ;
  MemoLogNaTela.ReadOnly := True;
  MemoLogNaTela.TabStop :=false;
  MemoLogNaTela.Color := clBtnFace;
  MemoLogNaTela.Font.Color := clBlack;
  BtCopiarLog.Enabled := False;
  BtAbrirLog.Enabled := False;
end;

procedure TFGerenciadorDePastas.FormShow(Sender: TObject);
begin
  btIniciar.Enabled := False;
  ComboBoxBranch.Enabled := False;
  ComboBoxSubPastas.Enabled := False;
  AdicionarLogNaTela('Carregando branches locais e referencias remotas em cache; nenhum fetch sera executado.');
  ObterBranchesUnicas(LerCaminhoGitDoINI, ListaDeRepositoriosGit, ComboBoxBranch.Items);
  ComboBoxBranch.Enabled := True;
  ComboBoxSubPastas.Enabled := True;
  btIniciar.Enabled := ComboBoxBranch.Items.Count > 0;
  AdicionarLogNaTela('Branches locais e remotas carregadas.');
end;
procedure TFGerenciadorDePastas.GuiaDeUsoClick(Sender: TObject);
var
  CaminhoPDF: string;
begin
  CaminhoPDF := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName)) +
                'Doc\GuiaDeUsuario.pdf';

  if FileExists(CaminhoPDF) then
    ShellExecute(0, 'open', PChar(CaminhoPDF), nil, nil, SW_SHOWNORMAL)
  else
    ShowMessage('O arquivo "GuiaDeUsuario.pdf" não foi encontrado na pasta Doc do sistema.');
end;

procedure TFGerenciadorDePastas.Logs();
var
  LogsDir, DataHoje, ArquivoLogAtual, FilePath: string;
  InfoArq: TSearchRec;
  Ret: Integer;
begin
  LogsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Logs');
  if not DirectoryExists(LogsDir) then
    ForceDirectories(LogsDir);

  DataHoje := FormatDateTime('dd-mm-yyyy', Now);

  Ret := FindFirst(PChar(TPath.Combine(LogsDir, 'cmd_git_*.log')), faAnyFile, InfoArq);
  if Ret = 0 then
  begin
    repeat
      if Pos(DataHoje, InfoArq.Name) = 0 then
      begin
        FilePath := TPath.Combine(LogsDir, InfoArq.Name);
        if FileExists(FilePath) then
          DeleteFile(FilePath);
      end;
      Ret := FindNext(InfoArq);
    until Ret <> 0;
    FindClose(InfoArq);
  end;

  ArquivoLogAtual := Format('cmd_git_%s.log', [FormatDateTime('dd-mm-yyyy_hh-nn-ss', Now)]);
  ArquivoLogAtual := TPath.Combine(LogsDir, ArquivoLogAtual);

  UClasseValidacao.ArquivoLogGlobal := ArquivoLogAtual;
end;

procedure TFGerenciadorDePastas.MemoLogNaTela1Change(Sender: TObject);
begin
  BtCopiarLog.Enabled := MemoLogNaTela.Lines.Count > 0;
  BtAbrirLog.Enabled := MemoLogNaTela.Lines.Count > 0;
end;

procedure TFGerenciadorDePastas.ReportdebugClick(Sender: TObject);
begin
  if not Assigned(FFormFeedBack) then
    Application.CreateForm(TFFormFeedBack, FFormFeedBack);

  FFormFeedBack.ShowModal;
end;

procedure VerificarRepositoriosGit(const Caminho: string);
var
  SubPastas: TStringDynArray;
  Pasta: string;
begin
  ListaDeRepositoriosGit.Clear;

  SubPastas := TDirectory.GetDirectories(Caminho);
  for Pasta in SubPastas do
  begin
    if TDirectory.Exists(TPath.Combine(Pasta, '.git')) or TFile.Exists(TPath.Combine(Pasta, '.git')) then
      ListaDeRepositoriosGit.Add(Pasta);
  end;
  ListaDeRepositoriosGit.Sort;

  if ListaDeRepositoriosGit.Count = 0 then
  begin
    try
      TFile.AppendAllText(ArquivoLogGlobal, 'Não há subpastas com repositório Git nessa pasta.', TEncoding.UTF8);
    except
      on E: Exception do
        ShowMessage('Erro ao gravar log: ' + E.Message);
    end;
    ShowMessage('Não há subpastas com repositório Git nessa pasta.');
    Application.Terminate;
  end;
end;

procedure TFGerenciadorDePastas.AdicionarLogNaTela(const Msg: string);
begin
  MemoLogNaTela.Lines.Add(Format('[%s] %s', [FormatDateTime('dd/mm/yyyy hh:nn:ss', Now), Msg]));
  MemoLogNaTela.SelStart := Length(MemoLogNaTela.Text); // rolar para o fim
end;

initialization
  ListaDeRepositoriosGit := TStringList.Create;

finalization
  ListaDeRepositoriosGit.Free;

end.

