unit UGerenciadorDePastasPrincipal;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, System.IOUtils, System.Types,
  Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls, UClasseValidacao, TFormConfiguracaoGerenciador, Clipbrd, ShellAPI, System.UITypes, RichEdit, UFeedBack,
  Vcl.ComCtrls, Vcl.Menus, StrUtils;

procedure VerificarRepositoriosGit(const Caminho: string);


type
  TFGerenciadorDePastas = class;

  TGitBatchThread = class(TThread)
  private
    FForm: TFGerenciadorDePastas;
    FBranchSelecionada: string;
    FRepositorios: TStringList;
    FMensagemPendente: string;
    FPosicaoProgresso: Integer;
    FErro: Boolean;
    procedure PublicarLog;
    procedure PublicarProgresso;
    procedure FinalizarNaInterface;
    procedure RegistrarLog(const Msg: string);
    procedure AtualizarProgresso(const Posicao: Integer);
    procedure ProcessarRepositorio(const PastaRepo: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AForm: TFGerenciadorDePastas; const Branch: string;
      const Repositorios: TStrings);
    destructor Destroy; override;
  end;

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
    procedure ComboBoxSubPastasChange(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

  private
    FBranchesDisponiveis: TStringList;
    FAtualizandoComboBranch: Boolean;
    FWorker: TGitBatchThread;
    procedure AtualizarListaBranches;
    procedure DefinirListaBranches(const Branches: TStrings);
    procedure ComboBoxBranchChange(Sender: TObject);
  public
    destructor Destroy; override;
    procedure AdicionarLogNaTela(const Msg: string);
    { Public declarations }
  end;

var
  FGerenciadorDePastas: TFGerenciadorDePastas;
  ListaDeRepositoriosGit: TStringList;
  SSHAuthSock: string;


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

function ComandoFalhou(const Resultado: string): Boolean;
begin
  Result := (CodigoSaidaUltimoGit <> 0) or
    (Pos('fatal', LowerCase(Resultado)) > 0) or
    (Pos('error', LowerCase(Resultado)) > 0) or
    (Pos('conflict', LowerCase(Resultado)) > 0);
end;

constructor TGitBatchThread.Create(AForm: TFGerenciadorDePastas;
  const Branch: string; const Repositorios: TStrings);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FForm := AForm;
  FBranchSelecionada := Branch;
  FRepositorios := TStringList.Create;
  FRepositorios.Assign(Repositorios);
end;

destructor TGitBatchThread.Destroy;
begin
  FRepositorios.Free;
  inherited;
end;

procedure TGitBatchThread.PublicarLog;
begin
  if Assigned(FForm) then
    FForm.AdicionarLogNaTela(FMensagemPendente);
end;

procedure TGitBatchThread.RegistrarLog(const Msg: string);
begin
  FMensagemPendente := Msg;
  Synchronize(PublicarLog);
end;

procedure TGitBatchThread.PublicarProgresso;
begin
  if Assigned(FForm) then
    FForm.ProgressBarCarregamento.Position := FPosicaoProgresso;
end;

procedure TGitBatchThread.AtualizarProgresso(const Posicao: Integer);
begin
  FPosicaoProgresso := Posicao;
  Synchronize(PublicarProgresso);
end;

procedure TGitBatchThread.FinalizarNaInterface;
begin
  if not Assigned(FForm) then
    Exit;

  if FErro then
    FForm.AdicionarLogNaTela('Processo concluido com repositorios ignorados ou erros.')
  else
    FForm.AdicionarLogNaTela('Processo concluido com sucesso.');

  FForm.btIniciar.Enabled :=
    FForm.ComboBoxBranch.Items.IndexOf(FForm.ComboBoxBranch.Text) >= 0;
  FForm.btSair.Enabled := True;
  FForm.ComboBoxBranch.Enabled := True;
  FForm.ComboBoxSubPastas.Enabled := True;
  FForm.Configuracao.Enabled := True;
  FForm.FWorker := nil;
end;

procedure TGitBatchThread.ProcessarRepositorio(const PastaRepo: string);
var
  BranchLocal, BranchRemota, NomeRemoto, NomeBranchRemota, Resultado: string;
  BranchLocalExiste: Boolean;
  Separador: Integer;
begin
  RegistrarLog('Processando: ' + PastaRepo);
  if ArquivoLogGlobal <> '' then
    TFile.AppendAllText(ArquivoLogGlobal,
      Format('Processando repositorio: %s | branch: %s%s',
        [PastaRepo, FBranchSelecionada, sLineBreak]), TEncoding.UTF8);

  BranchLocal := FBranchSelecionada;
  BranchRemota := '';
  NomeRemoto := '';
  NomeBranchRemota := '';
  BranchLocalExiste := False;

  if StartsText('remotes/', FBranchSelecionada) then
  begin
    BranchRemota := Copy(FBranchSelecionada, Length('remotes/') + 1, MaxInt);
    Separador := Pos('/', BranchRemota);
    if Separador = 0 then
    begin
      RegistrarLog('Referencia remota invalida; repositorio ignorado: ' + FBranchSelecionada);
      FErro := True;
      Exit;
    end;
    NomeRemoto := Copy(BranchRemota, 1, Separador - 1);
    NomeBranchRemota := Copy(BranchRemota, Separador + 1, MaxInt);
    BranchLocal := NomeBranchRemota;
  end;

  if BranchRemota <> '' then
  begin
    RegistrarLog('Verificando a branch remota no repositorio...');
    if not BranchRemotaExiste(PastaRepo, BranchRemota, ExecutarComandoGit) then
    begin
      RegistrarLog('Branch remota ausente; repositorio ignorado: ' + PastaRepo);
      FErro := True;
      Exit;
    end;
    BranchLocalExiste := BranchExiste(PastaRepo, BranchLocal, ExecutarComandoGit);
    if BranchLocalExiste then
      RegistrarLog('Branch local existente sera atualizada pela referencia remota selecionada: ' + BranchRemota)
    else
      RegistrarLog('Branch local inexistente; sera criada a partir de: ' + BranchRemota);
  end
  else
  begin
    RegistrarLog('Verificando a branch local no repositorio...');
    if not BranchExiste(PastaRepo, BranchLocal, ExecutarComandoGit) then
    begin
      RegistrarLog('Branch local ausente; repositorio ignorado: ' + PastaRepo);
      FErro := True;
      Exit;
    end;
  end;

  RegistrarLog('Verificando alteracoes locais...');
  if HaAlteracoesPendentes(PastaRepo, ExecutarComandoGit) then
  begin
    RegistrarLog('Alteracoes locais ou erro de status; repositorio ignorado: ' + PastaRepo);
    FErro := True;
    Exit;
  end;

  RegistrarLog('Verificando a branch atualmente selecionada...');
  if BranchAtual(PastaRepo, ExecutarComandoGit) <> BranchLocal then
  begin
    RegistrarLog('Executando checkout...');
    if (BranchRemota <> '') and not BranchLocalExiste then
      Resultado := ExecutarComandoGit('checkout --track -b ' + BranchLocal + ' ' + BranchRemota, PastaRepo)
    else
      Resultado := ExecutarComandoGit('checkout ' + BranchLocal, PastaRepo);
    if ComandoFalhou(Resultado) then
    begin
      RegistrarLog('Checkout falhou; pull nao executado: ' + Trim(Resultado));
      FErro := True;
      Exit;
    end;
  end
  else
    RegistrarLog('Branch ja estava selecionada.');

  RegistrarLog('Executando pull --ff-only...');
  if BranchRemota <> '' then
    Resultado := ExecutarComandoGit('pull --ff-only ' + NomeRemoto + ' ' + NomeBranchRemota, PastaRepo)
  else
    Resultado := ExecutarComandoGit('pull --ff-only', PastaRepo);

  if ComandoFalhou(Resultado) then
  begin
    RegistrarLog('Pull falhou: ' + Trim(Resultado));
    FErro := True;
  end
  else
    RegistrarLog('Checkout/pull concluido em: ' + PastaRepo);
end;

procedure TGitBatchThread.Execute;
var
  I: Integer;
begin
  FErro := False;
  try
    try
      for I := 0 to FRepositorios.Count - 1 do
      begin
        try
          ProcessarRepositorio(FRepositorios[I]);
        except
          on E: Exception do
          begin
            RegistrarLog('Erro ao processar repositorio ' + FRepositorios[I] + ': ' + E.Message);
            FErro := True;
          end;
        end;
        AtualizarProgresso(((I + 1) * 100) div FRepositorios.Count);
      end;
      if FRepositorios.Count = 0 then
        AtualizarProgresso(100);
    except
      on E: Exception do
      begin
        FErro := True;
        RegistrarLog('Erro inesperado no processamento: ' + E.Message);
      end;
    end;
  finally
    Synchronize(FinalizarNaInterface);
  end;
end;
procedure TFGerenciadorDePastas.btIniciarClick(Sender: TObject);
var
  BranchSelecionada, PastaSelecionada: string;
  Repositorios: TStringList;
  I: Integer;
begin
  if Assigned(FWorker) then
    Exit;

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
    btSair.Enabled := False;
    ComboBoxBranch.Enabled := False;
    ComboBoxSubPastas.Enabled := False;
    Configuracao.Enabled := False;
    MemoLogNaTela.Clear;
    ProgressBarCarregamento.Min := 0;
    ProgressBarCarregamento.Max := 100;
    ProgressBarCarregamento.Position := 0;
    AdicionarLogNaTela('Branch selecionada: ' + BranchSelecionada);
    AdicionarLogNaTela('A operacao usa somente checkout e pull --ff-only.');
    AdicionarLogNaTela('Os repositorios serao processados em sequencia.');

    try
      FWorker := TGitBatchThread.Create(Self, BranchSelecionada, Repositorios);
      FWorker.Start;
    except
      on E: Exception do
      begin
        FreeAndNil(FWorker);
        btSair.Enabled := True;
        ComboBoxBranch.Enabled := True;
        ComboBoxSubPastas.Enabled := True;
        Configuracao.Enabled := True;
        btIniciar.Enabled := ComboBoxBranch.Items.IndexOf(ComboBoxBranch.Text) >= 0;
        AdicionarLogNaTela('Nao foi possivel iniciar o processamento em segundo plano: ' + E.Message);
      end;
    end;
  finally
    Repositorios.Free;
  end;
end;
procedure TFGerenciadorDePastas.btSairClick(Sender: TObject);
begin
  if Assigned(FWorker) then
  begin
    ShowMessage('Aguarde o processamento dos repositorios terminar antes de sair.');
    Exit;
  end;
  Application.Terminate;
end;

procedure TFGerenciadorDePastas.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
begin
  CanClose := not Assigned(FWorker);
  if not CanClose then
    ShowMessage('O processamento Git ainda esta em andamento. Aguarde a conclusao antes de fechar o programa.');
end;
procedure TFGerenciadorDePastas.ComboBoxSubPastasChange(Sender: TObject);
var
  SubpastaSelecionada: string;
  Repositorios: TStringList;
  ListaBranches: TStringList;
  I: Integer;
  CaminhoCompleto: string;
begin
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
    DefinirListaBranches(ListaBranches);

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

destructor TFGerenciadorDePastas.Destroy;
begin
  FBranchesDisponiveis.Free;
  inherited;
end;

procedure TFGerenciadorDePastas.DefinirListaBranches(const Branches: TStrings);
begin
  if Branches <> FBranchesDisponiveis then
    FBranchesDisponiveis.Assign(Branches);

  FAtualizandoComboBranch := True;
  try
    ComboBoxBranch.Items.BeginUpdate;
    try
      ComboBoxBranch.Items.Assign(FBranchesDisponiveis);
      ComboBoxBranch.Text := '';
    finally
      ComboBoxBranch.Items.EndUpdate;
    end;
  finally
    FAtualizandoComboBranch := False;
  end;
  btIniciar.Enabled := False;
end;

procedure TFGerenciadorDePastas.AtualizarListaBranches;
var
  TextoBusca, Branch: string;
  PosicaoCursor: Integer;
begin
  if FAtualizandoComboBranch then
    Exit;

  TextoBusca := ComboBoxBranch.Text;
  PosicaoCursor := ComboBoxBranch.SelStart;
  FAtualizandoComboBranch := True;
  try
    ComboBoxBranch.Items.BeginUpdate;
    try
      ComboBoxBranch.Items.Clear;
      for Branch in FBranchesDisponiveis do
        if (TextoBusca = '') or ContainsText(Branch, TextoBusca) then
          ComboBoxBranch.Items.Add(Branch);
    finally
      ComboBoxBranch.Items.EndUpdate;
    end;
    ComboBoxBranch.Text := TextoBusca;
    if PosicaoCursor > Length(TextoBusca) then
      PosicaoCursor := Length(TextoBusca);
    ComboBoxBranch.SelStart := PosicaoCursor;
    ComboBoxBranch.SelLength := 0;
  finally
    FAtualizandoComboBranch := False;
  end;

  ComboBoxBranch.DroppedDown := (TextoBusca <> '') and (ComboBoxBranch.Items.Count > 0);
  btIniciar.Enabled := ComboBoxBranch.Items.IndexOf(ComboBoxBranch.Text) >= 0;
end;

procedure TFGerenciadorDePastas.ComboBoxBranchChange(Sender: TObject);
begin
  if FAtualizandoComboBranch then
    Exit;

  if ComboBoxBranch.ItemIndex >= 0 then
  begin
    btIniciar.Enabled := True;
    Exit;
  end;

  AtualizarListaBranches;
end;
procedure TFGerenciadorDePastas.FormCreate(Sender: TObject);
var
  DataHoje, CaminhoDebug, ArquivoLogAtual, CaminhoGit, CaminhoProjetos: string;
  InfoArq: TSearchRec;
begin
  FBranchesDisponiveis := TStringList.Create;
  ComboBoxBranch.OnChange := ComboBoxBranchChange;
  btIniciar.Enabled := False;
  OnLogMensagem := AdicionarLogNaTela;
  OnCloseQuery := FormCloseQuery;
  FWorker := nil;
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
  FBranchesDisponiveis.Clear;
  ObterBranchesUnicas(LerCaminhoGitDoINI, ListaDeRepositoriosGit, FBranchesDisponiveis);
  DefinirListaBranches(FBranchesDisponiveis);
  ComboBoxBranch.Enabled := True;
  ComboBoxSubPastas.Enabled := True;
  btIniciar.Enabled := False;
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

