unit TFormConfiguracaoGerenciador;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.Buttons, System.IniFiles, System.IOUtils, FileCtrl;

type
  TUConfiguracao = class(TForm)
    OpenDialogConfiguracao: TOpenDialog;
    BtPesquisar: TBitBtn;
    EdCaminhoGitText: TEdit;
    LabelTex: TLabel;
    LabelStatusGit: TLabel;
    LabelAuthTitle: TLabel;
    LabelAuthHelp: TLabel;
    CheckUsarPuTTY: TCheckBox;
    Label1: TLabel;
    EdCaminhoPutty: TEdit;
    BtPesquisarPuTTy: TBitBtn;
    LabelPuttyKey: TLabel;
    EditPuTTyKey: TEdit;
    BTPuTTYKey: TBitBtn;
    BtValidar: TBitBtn;
    BtSalvar: TBitBtn;
    BttSair: TBitBtn;
    procedure BtPesquisarClick(Sender: TObject);
    procedure BtSalvarClick(Sender: TObject);
    procedure BttSairClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure BtPesquisarPuTTyClick(Sender: TObject);
    procedure BTPuTTYKeyClick(Sender: TObject);
    procedure BtValidarClick(Sender: TObject);
    procedure CheckUsarPuTTYClick(Sender: TObject);
    procedure EdCaminhoGitTextChange(Sender: TObject);
  private
    FGitValidadoPath: string;
    procedure AtualizarLayout;
    procedure AtualizarStatusGit(const Validado: Boolean; const Mensagem: string = '');
  public
    ModoInicial: Boolean;
    class function Execute: Boolean;
  end;

var
  UConfiguracao: TUConfiguracao;
  CaminhoGit: string;
  CaminhoPadraoPutty: string = '';

implementation

{$R *.dfm}

function GitExeDoDiretorio(const Diretorio: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Trim(Diretorio)) + 'git.exe';
end;

function DiretorioContemGit(const Diretorio: string): Boolean;
begin
  Result := (Trim(Diretorio) <> '') and FileExists(GitExeDoDiretorio(Diretorio));
end;

function DetectarGitInstalado(const CaminhoSalvo: string): string;
var
  Candidatos: TStringList;
  Base, Candidato: string;
  Buffer: array[0..MAX_PATH] of Char;
  Tamanho: Cardinal;
  ParteArquivo: PChar;
  I: Integer;

  procedure AdicionarBase(const Raiz: string);
  begin
    if Trim(Raiz) = '' then
      Exit;
    Candidatos.Add(TPath.Combine(Raiz, 'Git\bin'));
    Candidatos.Add(TPath.Combine(Raiz, 'Git\cmd'));
  end;

begin
  Result := '';
  if DiretorioContemGit(CaminhoSalvo) then
    Exit(IncludeTrailingPathDelimiter(Trim(CaminhoSalvo)));

  Candidatos := TStringList.Create;
  try
    AdicionarBase(GetEnvironmentVariable('ProgramFiles'));
    AdicionarBase(GetEnvironmentVariable('ProgramFiles(x86)'));
    AdicionarBase(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Programs'));
    for I := 0 to Candidatos.Count - 1 do
    begin
      Candidato := Candidatos[I];
      if DiretorioContemGit(Candidato) then
        Exit(IncludeTrailingPathDelimiter(Candidato));
    end;
  finally
    Candidatos.Free;
  end;

  ParteArquivo := nil;
  Tamanho := SearchPath(nil, PChar('git.exe'), nil, Cardinal(Length(Buffer)), @Buffer[0], ParteArquivo);
  if (Tamanho > 0) and (Tamanho < Cardinal(Length(Buffer))) then
  begin
    Base := ExtractFilePath(string(PChar(@Buffer[0])));
    if DiretorioContemGit(Base) then
      Result := IncludeTrailingPathDelimiter(Base);
  end;
end;

function ExecutarGitVersion(const Diretorio: string; out Versao, Erro: string): Boolean;
var
  SecurityAttr: TSecurityAttributes;
  PipeLeitura, PipeEscrita: THandle;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  Comando, Trecho: string;
  TrechoAnsi: AnsiString;
  Buffer: array[0..511] of AnsiChar;
  BytesLidos, CodigoSaida: DWORD;
  Espera: DWORD;
begin
  Result := False;
  Versao := '';
  Erro := '';
  PipeLeitura := 0;
  PipeEscrita := 0;
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);

  if not DiretorioContemGit(Diretorio) then
  begin
    Erro := 'O arquivo git.exe nao foi encontrado na pasta informada.';
    Exit;
  end;

  FillChar(SecurityAttr, SizeOf(SecurityAttr), 0);
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := True;
  if not CreatePipe(PipeLeitura, PipeEscrita, @SecurityAttr, 0) then
  begin
    Erro := 'Nao foi possivel iniciar a validacao do Git.';
    Exit;
  end;

  try
    SetHandleInformation(PipeLeitura, HANDLE_FLAG_INHERIT, 0);
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.wShowWindow := SW_HIDE;
    StartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    StartupInfo.hStdOutput := PipeEscrita;
    StartupInfo.hStdError := PipeEscrita;

    Comando := '"' + GitExeDoDiretorio(Diretorio) + '" --version';
    UniqueString(Comando);
    if not CreateProcess(nil, PChar(Comando), nil, nil, True, CREATE_NO_WINDOW,
      nil, PChar(Trim(Diretorio)), StartupInfo, ProcessInfo) then
    begin
      Erro := 'Nao foi possivel executar git.exe. Codigo do Windows: ' +
        IntToStr(GetLastError) + '.';
      Exit;
    end;

    CloseHandle(PipeEscrita);
    PipeEscrita := 0;
    try
      Espera := WaitForSingleObject(ProcessInfo.hProcess, 5000);
      if Espera = WAIT_TIMEOUT then
      begin
        TerminateProcess(ProcessInfo.hProcess, 1);
        Erro := 'A validacao do Git excedeu o tempo limite.';
        Exit;
      end;

      while ReadFile(PipeLeitura, Buffer, SizeOf(Buffer), BytesLidos, nil) and
        (BytesLidos > 0) do
      begin
        SetString(TrechoAnsi, PAnsiChar(@Buffer[0]), BytesLidos);
        Trecho := string(TrechoAnsi);
        Versao := Versao + Trecho;
      end;

      CodigoSaida := 1;
      GetExitCodeProcess(ProcessInfo.hProcess, CodigoSaida);
      Versao := Trim(Versao);
      Result := (CodigoSaida = 0) and (Versao <> '');
      if not Result then
        Erro := 'O git.exe foi localizado, mas nao respondeu corretamente ao comando --version.';
    finally
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
  finally
    if PipeEscrita <> 0 then
      CloseHandle(PipeEscrita);
    if PipeLeitura <> 0 then
      CloseHandle(PipeLeitura);
  end;
end;

function GetCaminhoINI: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ConfigGit.ini';
end;

function LerCaminhoGitDoINI: string;
var
  Ini: TIniFile;
begin
  Result := '';
  if not FileExists(GetCaminhoINI) then
    Exit;
  Ini := TIniFile.Create(GetCaminhoINI);
  try
    Result := Ini.ReadString('GIT', 'Caminho', '');
  finally
    Ini.Free;
  end;
end;

function LerCaminhoPPKDoINI: string;
var
  Ini: TIniFile;
begin
  Result := '';
  if not FileExists(GetCaminhoINI) then
    Exit;
  Ini := TIniFile.Create(GetCaminhoINI);
  try
    Result := Ini.ReadString('PUTTY', 'CaminhoPPK', '');
  finally
    Ini.Free;
  end;
end;

function LerCaminhoEXEPPKDoINI: string;
var
  Ini: TIniFile;
begin
  Result := '';
  if not FileExists(GetCaminhoINI) then
    Exit;
  Ini := TIniFile.Create(GetCaminhoINI);
  try
    Result := Ini.ReadString('PUTTY', 'CaminhoEXE', '');
  finally
    Ini.Free;
  end;
end;

procedure TUConfiguracao.AtualizarStatusGit(const Validado: Boolean; const Mensagem: string);
begin
  if Mensagem <> '' then
  begin
    LabelStatusGit.Caption := Mensagem;
    LabelStatusGit.Font.Color := clRed;
    FGitValidadoPath := '';
    Exit;
  end;

  if not DiretorioContemGit(EdCaminhoGitText.Text) then
  begin
    LabelStatusGit.Caption := 'git.exe nao encontrado nesse caminho.';
    LabelStatusGit.Font.Color := clRed;
    FGitValidadoPath := '';
  end
  else if Validado then
  begin
    LabelStatusGit.Caption := 'Git validado: ' + FGitValidadoPath;
    LabelStatusGit.Font.Color := clGreen;
  end
  else
  begin
    LabelStatusGit.Caption := 'git.exe encontrado. Clique em "Validar Git" para testar.';
    LabelStatusGit.Font.Color := clWindowText;
    FGitValidadoPath := '';
  end;
end;

procedure TUConfiguracao.AtualizarLayout;
begin
  Label1.Visible := CheckUsarPuTTY.Checked;
  EdCaminhoPutty.Visible := CheckUsarPuTTY.Checked;
  BtPesquisarPuTTy.Visible := CheckUsarPuTTY.Checked;
  LabelPuttyKey.Visible := CheckUsarPuTTY.Checked;
  EditPuTTyKey.Visible := CheckUsarPuTTY.Checked;
  BTPuTTYKey.Visible := CheckUsarPuTTY.Checked;
  if CheckUsarPuTTY.Checked then
  begin
    BtValidar.Top := 294;
    BtSalvar.Top := 294;
    BttSair.Top := 294;
    ClientHeight := 340;
  end
  else
  begin
    BtValidar.Top := 195;
    BtSalvar.Top := 195;
    BttSair.Top := 195;
    ClientHeight := 238;
  end;
end;

procedure TUConfiguracao.BtPesquisarClick(Sender: TObject);
var
  PastaSelecionada: string;
begin
  if SelectDirectory('Selecione a pasta que contem o git.exe', EdCaminhoGitText.Text, PastaSelecionada) then
  begin
    EdCaminhoGitText.Text := PastaSelecionada;
    AtualizarStatusGit(False);
  end;
end;

procedure TUConfiguracao.BtPesquisarPuTTyClick(Sender: TObject);
var
  PastaSelecionada: string;
begin
  if SelectDirectory('Selecione a pasta do PuTTY (plink.exe)', EdCaminhoPutty.Text, PastaSelecionada) then
    EdCaminhoPutty.Text := PastaSelecionada;
end;

procedure TUConfiguracao.BTPuTTYKeyClick(Sender: TObject);
begin
  OpenDialogConfiguracao.Title := 'Selecione a chave privada PuTTY';
  OpenDialogConfiguracao.Filter := 'Chave PuTTY (*.ppk)|*.ppk';
  OpenDialogConfiguracao.Options := [ofFileMustExist, ofPathMustExist];
  if OpenDialogConfiguracao.Execute then
    EditPuTTyKey.Text := OpenDialogConfiguracao.FileName;
end;

procedure TUConfiguracao.BtValidarClick(Sender: TObject);
var
  Versao, Erro, Diretorio, DiretorioPuTTY, ArquivoPPK: string;
begin
  Diretorio := IncludeTrailingPathDelimiter(Trim(EdCaminhoGitText.Text));
  if not ExecutarGitVersion(Diretorio, Versao, Erro) then
  begin
    AtualizarStatusGit(False, Erro);
    ShowMessage(Erro);
    Exit;
  end;

  if CheckUsarPuTTY.Checked then
  begin
    DiretorioPuTTY := IncludeTrailingPathDelimiter(Trim(EdCaminhoPutty.Text));
    ArquivoPPK := Trim(EditPuTTyKey.Text);
    if not DirectoryExists(DiretorioPuTTY) or
       not FileExists(TPath.Combine(DiretorioPuTTY, 'plink.exe')) or
       not FileExists(TPath.Combine(DiretorioPuTTY, 'pageant.exe')) then
    begin
      ShowMessage('A pasta PuTTY informada deve conter plink.exe e pageant.exe.');
      Exit;
    end;
    if (ArquivoPPK = '') or not FileExists(ArquivoPPK) or
       not SameText(ExtractFileExt(ArquivoPPK), '.ppk') then
    begin
      ShowMessage('Selecione um arquivo de chave PuTTY valido com extensao .ppk.');
      Exit;
    end;
  end;

  FGitValidadoPath := Diretorio;
  LabelStatusGit.Caption := 'Validado: ' + Versao;
  LabelStatusGit.Font.Color := clGreen;
  if CheckUsarPuTTY.Checked then
    ShowMessage('Git e PuTTY validados. A chave precisa estar desbloqueada no Pageant e a chave de host do servidor deve ter sido aceita previamente.')
  else
    ShowMessage('Git validado: ' + Versao + '. A autenticacao usara a configuracao existente do Git.');
end;

procedure TUConfiguracao.CheckUsarPuTTYClick(Sender: TObject);
begin
  AtualizarLayout;
end;

procedure TUConfiguracao.EdCaminhoGitTextChange(Sender: TObject);
begin
  AtualizarStatusGit(False);
end;

procedure TUConfiguracao.BtSalvarClick(Sender: TObject);
var
  Caminho, CaminhoPuTTY, CaminhoPPK, Versao, Erro: string;
  Ini: TIniFile;
begin
  Caminho := IncludeTrailingPathDelimiter(Trim(EdCaminhoGitText.Text));
  if not ExecutarGitVersion(Caminho, Versao, Erro) then
  begin
    AtualizarStatusGit(False, Erro);
    ShowMessage(Erro);
    Exit;
  end;

  CaminhoPuTTY := IncludeTrailingPathDelimiter(Trim(EdCaminhoPutty.Text));
  CaminhoPPK := Trim(EditPuTTyKey.Text);
  if CheckUsarPuTTY.Checked then
  begin
    if not DirectoryExists(CaminhoPuTTY) or
       not FileExists(TPath.Combine(CaminhoPuTTY, 'plink.exe')) or
       not FileExists(TPath.Combine(CaminhoPuTTY, 'pageant.exe')) then
    begin
      ShowMessage('Selecione uma pasta PuTTY valida contendo plink.exe e pageant.exe.');
      EdCaminhoPutty.SetFocus;
      Exit;
    end;
    if (CaminhoPPK = '') or not FileExists(CaminhoPPK) or
       not SameText(ExtractFileExt(CaminhoPPK), '.ppk') then
    begin
      ShowMessage('Selecione um arquivo de chave PuTTY valido com extensao .ppk.');
      EditPuTTyKey.SetFocus;
      Exit;
    end;
  end;

  Ini := TIniFile.Create(GetCaminhoINI);
  try
    Ini.WriteString('GIT', 'Caminho', Caminho);
    if CheckUsarPuTTY.Checked then
    begin
      Ini.WriteString('PUTTY', 'CaminhoPPK', CaminhoPPK);
      Ini.WriteString('PUTTY', 'CaminhoEXE', ExcludeTrailingPathDelimiter(CaminhoPuTTY));
    end
    else
      Ini.EraseSection('PUTTY');
    Ini.EraseSection('TORTOISEGIT');
  finally
    Ini.Free;
  end;

  CaminhoGit := Caminho;
  FGitValidadoPath := Caminho;
  LabelStatusGit.Caption := 'Validado: ' + Versao;
  LabelStatusGit.Font.Color := clGreen;
  ShowMessage('Configuracoes salvas com sucesso.');
  ModalResult := mrOk;
end;

procedure TUConfiguracao.BttSairClick(Sender: TObject);
begin
  if LerCaminhoGitDoINI = '' then
    Application.Terminate
  else
    ModalResult := mrCancel;
end;

class function TUConfiguracao.Execute: Boolean;
var
  Frm: TUConfiguracao;
begin
  Frm := TUConfiguracao.Create(nil);
  try
    Result := Frm.ShowModal = mrOk;
  finally
    Frm.Free;
  end;
end;

procedure TUConfiguracao.FormCreate(Sender: TObject);
var
  CaminhoSalvo, CaminhoDetectado: string;
begin
  CaminhoSalvo := LerCaminhoGitDoINI;
  CaminhoDetectado := DetectarGitInstalado(CaminhoSalvo);
  if CaminhoDetectado <> '' then
    EdCaminhoGitText.Text := CaminhoDetectado
  else
    EdCaminhoGitText.Text := CaminhoSalvo;

  EdCaminhoPutty.Text := LerCaminhoEXEPPKDoINI;
  EditPuTTyKey.Text := LerCaminhoPPKDoINI;
  CheckUsarPuTTY.Checked := (Trim(EdCaminhoPutty.Text) <> '') or
    (Trim(EditPuTTyKey.Text) <> '');
  FGitValidadoPath := '';
  AtualizarLayout;
  AtualizarStatusGit(False);
end;

end.