unit UClasseValidacao;

interface

uses
  System.SysUtils, System.IOUtils, System.IniFiles, Vcl.Dialogs, TFormConfiguracaoGerenciador, System.Classes, ShellAPI, TlHelp32, Winapi.Windows, Forms,
  Vcl.Controls, System.Types,Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls, Clipbrd, System.UITypes, RichEdit, Vcl.ComCtrls, Vcl.Menus, StrUtils;

function CaminhoDoINI: string;
function INIExiste: Boolean;
function CaminhoPadraoGit: string;
function GitNoCaminhoPadraoExiste: Boolean;
procedure CriarINIComCaminhoPadrao;
function LerCaminhoGitDoINI: string;
function CaminhoGitEhValido(const CaminhoGit: string): Boolean;
procedure ValidarConfiguracaoGit;
function NovaConfiguracaoGit: Boolean;
procedure ObterBranchesUnicas(const CaminhoGitBin: string; const Repositorios: TStrings; const ListaBranches: TStrings);
function ExecutarComandoGit(const Comando, Pasta: string): string;
function ExecutarComandoGitSSH(const Comando, Pasta: string): string;
function ExecutarComandoGitSSHComEnv(const Comando, Pasta: string): string;
type
  TLogCallback = procedure(const Msg: string) of object;
  TGitExecutor = function(const Comando, Pasta: string): string;
function BranchAtual(const Pasta: string; Exec: TGitExecutor): string;
function BranchExiste(const Pasta, Branch: string; Exec: TGitExecutor): Boolean;
function BranchRemotaExiste(const Pasta, Branch: string; Exec: TGitExecutor): Boolean;
function HaAlteracoesPendentes(const Pasta: string; Exec: TGitExecutor): Boolean;


var
   OnLogMensagem: TLogCallback;
   ArquivoLogGlobal: string = '';
   SSHAuthSock: string;
   CodigoSaidaUltimoGit: Cardinal;


implementation

uses
UGerenciadorDePastasPrincipal;

function CaminhoDoINI: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ConfigGit.ini';
end;


function GetSSHAuthSock: string;
begin
  Result := GetEnvironmentVariable('SSH_AUTH_SOCK');
end;


function NovaConfiguracaoGit: Boolean;
var
  UConfiguracao: TUConfiguracao;
begin
  Result := False;
  UConfiguracao := TUConfiguracao.Create(nil);
  try
    Result := (UConfiguracao.ShowModal = mrOk);
  finally
    UConfiguracao.Free;
  end;
end;

function INIExiste: Boolean;
begin
  Result := FileExists(CaminhoDoINI);
end;

function CaminhoPadraoGit: string;
begin
  Result := 'C:\Program Files\Git\bin\';
end;

function GitNoCaminhoPadraoExiste: Boolean;
begin
  Result := DirectoryExists(CaminhoPadraoGit);
end;

procedure CriarINIComCaminhoPadrao;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(CaminhoDoINI);
  try
    Ini.WriteString('GIT', 'Caminho', CaminhoPadraoGit);
  finally
    Ini.Free;
  end;
end;

function LerCaminhoGitDoINI: string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'ConfigGit.ini');
  try
    Result := Ini.ReadString('GIT', 'Caminho', '');
  finally
    Ini.Free;
  end;
end;

function LerCaminhoPuTTYDoINI: string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'ConfigGit.ini');
  try
    Result := Ini.ReadString('PUTTY', 'CaminhoPPK', '');
  finally
    Ini.Free;
  end;
end;

function LerCaminhoExePuTTYDoINI: string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'ConfigGit.ini');
  try
    Result := Ini.ReadString('PUTTY', 'CaminhoEXE', '');
  finally
    Ini.Free;
  end;
end;

function CaminhoGitEhValido(const CaminhoGit: string): Boolean;
begin
  Result := DirectoryExists(CaminhoGit);
end;

function LerCaminhoTortoiseGitDoINI: string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'ConfigGit.ini');
  try
    Result := Ini.ReadString('TORTOISEGIT', 'CaminhoBin', '');
  finally
    Ini.Free;
  end;
end;

function PuttyNoCaminhoPadraoExiste: Boolean;
const
  CaminhoPuttyPadrao = 'C:\Program Files\PuTTY';
begin
  Result := DirectoryExists(CaminhoPuttyPadrao);
  if Result then
  Begin
    TFormConfiguracaoGerenciador.CaminhoPadraoPutty := CaminhoPuttyPadrao;
    if LerCaminhoExePuTTYDoINI <> '' then
    begin
      TFile.AppendAllText(ArquivoLogGlobal,'PuTTY foi detectado no caminho padrão. Caso use configurações de segurança, configure-as no Gerenciador de Pastas.');
    end;
  End;
end;

function PageantEstaRodando: Boolean;
var
  SnapShot: THandle;
  ProcEntry: TProcessEntry32;
begin
  Result := False;
  SnapShot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if SnapShot = INVALID_HANDLE_VALUE then Exit;

  ProcEntry.dwSize := SizeOf(TProcessEntry32);
  if Process32First(SnapShot, ProcEntry) then
  begin
    repeat
      if SameText(ExtractFileName(ProcEntry.szExeFile), 'pageant.exe') then
      begin
        Result := True;
        Break;
      end;
    until not Process32Next(SnapShot, ProcEntry);
  end;
  CloseHandle(SnapShot);
end;

procedure ValidarConfiguracaoGit;
var
  CaminhoGit, CaminhoPuttyExe, CaminhoPuttyPPK, PlinkExe, ComandoPageant,
    Parametros: string;
  ShellResult: HINST;
begin
  if not INIExiste then
  begin
    if GitNoCaminhoPadraoExiste then
      CriarINIComCaminhoPadrao
    else
    begin
      ShowMessage('Git nao foi encontrado no caminho padrao ou nao esta instalado. Selecione a pasta bin do Git para continuar.');
      if not TUConfiguracao.Execute then
        Halt;
      Exit;
    end;
  end;

  CaminhoGit := LerCaminhoGitDoINI;
  if not CaminhoGitEhValido(CaminhoGit) then
  begin
    ShowMessage('O caminho do Git no arquivo de configuracao esta incorreto.');
    if not TUConfiguracao.Execute then
      Halt;
    CaminhoGit := LerCaminhoGitDoINI;
    if not CaminhoGitEhValido(CaminhoGit) then
      Exit;
  end;

  CaminhoPuttyExe := Trim(LerCaminhoExePuTTYDoINI);
  CaminhoPuttyPPK := Trim(LerCaminhoPuTTYDoINI);

  // Sem configuracao PuTTY, o Git usa seus helpers e autenticacao existentes.
  if (CaminhoPuttyExe = '') and (CaminhoPuttyPPK = '') then
    Exit;

  PlinkExe := TPath.Combine(CaminhoPuttyExe, 'plink.exe');
  ComandoPageant := TPath.Combine(CaminhoPuttyExe, 'pageant.exe');
  if (CaminhoPuttyExe = '') or (CaminhoPuttyPPK = '') or
     not DirectoryExists(CaminhoPuttyExe) or not FileExists(PlinkExe) or
     not FileExists(ComandoPageant) or not FileExists(CaminhoPuttyPPK) or
     not SameText(ExtractFileExt(CaminhoPuttyPPK), '.ppk') then
  begin
    if Assigned(OnLogMensagem) then
      OnLogMensagem('Configuracao PuTTY incompleta/invalida. Corrija ou desative PuTTY nas configuracoes; o programa nao vai trocar silenciosamente para outro metodo.');
    Exit;
  end;

  Parametros := '"' + CaminhoPuttyPPK + '"';
  ShellResult := ShellExecute(0, 'open', PChar(ComandoPageant), PChar(Parametros), nil, SW_SHOWNORMAL);
  if NativeInt(ShellResult) <= 32 then
  begin
    if Assigned(OnLogMensagem) then
      OnLogMensagem('Nao foi possivel iniciar Pageant para carregar a chave PPK. Codigo: ' + IntToStr(NativeInt(ShellResult)));
  end
  else if Assigned(OnLogMensagem) then
    OnLogMensagem('Pageant foi chamado para carregar a chave PPK configurada. Se a chave tiver senha, desbloqueie-a no Pageant antes de executar.');
end;
procedure ObterBranchesUnicas(const CaminhoGitBin: string; const Repositorios: TStrings; const ListaBranches: TStrings);
var
  PastaRepo, Cmd, Linha, LinhaTratada, NomeBranch: string;
  Saida, Locais, Remotas: TStringList;
  I: Integer;
  ProcessInfo: TProcessInformation;
  StartupInfo: TStartupInfo;
  SecurityAttr: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  Buffer: array[0..1023] of AnsiChar;
  BytesRead: DWORD;
  CmdLineW: WideString;
  CmdLinePW: PWideChar;
begin
  ListaBranches.Clear;
  Locais := TStringList.Create;
  Remotas := TStringList.Create;
  Saida := TStringList.Create;

  try
    for I := 0 to Repositorios.Count - 1 do
    begin
      PastaRepo := Repositorios[I];
      Saida.Clear;

      Cmd := Format('"%sgit.exe" -C "%s" for-each-ref --format="%%(refname)" refs/heads refs/remotes', [CaminhoGitBin, PastaRepo]);
      CmdLineW := '"cmd.exe" /c "' + Cmd + '"';
      CmdLinePW := PWideChar(CmdLineW);

      ZeroMemory(@SecurityAttr, SizeOf(SecurityAttr));
      SecurityAttr.nLength := SizeOf(SecurityAttr);
      SecurityAttr.bInheritHandle := True;

      if not CreatePipe(ReadPipe, WritePipe, @SecurityAttr, 0) then
        Continue;

      ZeroMemory(@StartupInfo, SizeOf(StartupInfo));
      StartupInfo.cb := SizeOf(StartupInfo);
      StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
      StartupInfo.hStdOutput := WritePipe;
      StartupInfo.hStdError := WritePipe;
      StartupInfo.wShowWindow := SW_HIDE;

      if CreateProcessW(nil, CmdLinePW, nil, nil, True, CREATE_NO_WINDOW, nil, nil, StartupInfo, ProcessInfo) then
      begin
        CloseHandle(WritePipe);
        FillChar(Buffer, SizeOf(Buffer), 0);
        repeat
          ReadFile(ReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil);
          if BytesRead > 0 then
          begin
            Buffer[BytesRead] := #0;
            Saida.Text := Saida.Text + string(PAnsiChar(@Buffer));
          end;
        until BytesRead = 0;

        for Linha in Saida do
        begin
          LinhaTratada := Trim(Linha);
          if LinhaTratada.StartsWith('refs/heads/') then
          begin
            NomeBranch := Copy(LinhaTratada, Length('refs/heads/') + 1, MaxInt);
            if (NomeBranch <> '') and (Locais.IndexOf(NomeBranch) = -1) then
              Locais.Add(NomeBranch);
          end
          else if LinhaTratada.StartsWith('refs/remotes/') and (not LinhaTratada.EndsWith('/HEAD')) then
          begin
            NomeBranch := Copy(LinhaTratada, Length('refs/remotes/') + 1, MaxInt);
            if (NomeBranch <> '') and (Remotas.IndexOf('remotes/' + NomeBranch) = -1) then
              Remotas.Add('remotes/' + NomeBranch);
          end;
        end;

        CloseHandle(ProcessInfo.hProcess);
        CloseHandle(ProcessInfo.hThread);
      end;
      CloseHandle(ReadPipe);
    end;

    Locais.Sort;
    Remotas.Sort;

    ListaBranches.AddStrings(Locais);
    ListaBranches.AddStrings(Remotas);

    if (Trim(ArquivoLogGlobal) <> '') then
      TFile.AppendAllText(ArquivoLogGlobal, CmdLineW + sLineBreak);

  finally
    Locais.Free;
    Remotas.Free;
    Saida.Free;
  end;
end;

function PathToBash(const WindowsPath: string): string;
begin
  // Exemplo: C:\Projetos\Teste ? /c/Projetos/Teste
  Result := StringReplace(WindowsPath, '\', '/', [rfReplaceAll]);
  if Length(Result) > 2 then
    if Result[2] = ':' then
      Result := '/' + LowerCase(Result[1]) + Copy(Result, 3, MaxInt);
end;

function QuoteCommandLineArgument(const Value: string): string;
var
  I, BackslashCount: Integer;
  C: Char;
begin
  Result := '"';
  BackslashCount := 0;
  for I := 1 to Length(Value) do
  begin
    C := Value[I];
    if C = #92 then
      Inc(BackslashCount)
    else
    begin
      if C = '"' then
        Result := Result + StringOfChar(#92, BackslashCount * 2 + 1) + '"'
      else
        Result := Result + StringOfChar(#92, BackslashCount) + C;
      BackslashCount := 0;
    end;
  end;
  Result := Result + StringOfChar(#92, BackslashCount * 2) + '"';
end;

function GitCommandPermitido(const Comando: string): Boolean;
var
  Args, NomeBranch, RefRemota: string;
  Separador: Integer;
begin
  Result := SameText(Trim(Comando), 'status --porcelain') or
            SameText(Trim(Comando), 'rev-parse --abbrev-ref HEAD') or
            SameText(Trim(Comando), 'branch --list --format="%(refname:short)"') or
            SameText(Trim(Comando), 'for-each-ref --format="%(refname:short)" refs/remotes') or
            SameText(Trim(Comando), 'pull --ff-only');
  if Result then
    Exit;

  Args := Trim(Comando);
  if StartsText('pull --ff-only ', Args) then
  begin
    Args := Trim(Copy(Args, Length('pull --ff-only ') + 1, MaxInt));
    Separador := Pos(' ', Args);
    if Separador <= 1 then
      Exit(False);
    NomeBranch := Copy(Args, 1, Separador - 1); // nome do remote
    RefRemota := Copy(Args, Separador + 1, MaxInt);
    Result := (NomeBranch <> '') and (RefRemota <> '') and
              (Pos(' ', RefRemota) = 0) and (Pos('"', Args) = 0) and
              (NomeBranch[1] <> '-') and (RefRemota[1] <> '-');
    Exit;
  end;

  if StartsText('checkout ', Args) and
     (not StartsText('checkout --', Args)) then
  begin
    NomeBranch := Trim(Copy(Args, Length('checkout ') + 1, MaxInt));
    Result := (NomeBranch <> '') and (Pos(' ', NomeBranch) = 0) and
              (NomeBranch[1] <> '-') and (Pos('"', NomeBranch) = 0);
    Exit;
  end;

  Result := False;
  if not StartsText('checkout --track -b ', Args) then
    Exit;
  Args := Trim(Copy(Args, Length('checkout --track -b ') + 1, MaxInt));
  Separador := Pos(' ', Args);
  if Separador <= 1 then
    Exit;
  NomeBranch := Copy(Args, 1, Separador - 1);
  RefRemota := Copy(Args, Separador + 1, MaxInt);
  Result := (NomeBranch <> '') and (RefRemota <> '') and
            (Pos(' ', RefRemota) = 0) and (Pos('"', Args) = 0) and
            (NomeBranch[1] <> '-') and (RefRemota[1] <> '-') and
            (Pos('/', RefRemota) > 1) and
            (RefRemota[Length(RefRemota)] <> '/');
end;
function ExecutarComandoGit(const Comando, Pasta: string): string;
const
  TEMPO_MAXIMO_GIT_MS = 30 * 60 * 1000;
var
  GitExe, CommandLine, PuttyDir, PuttyKey, PlinkExe, SSHCommand,
    TextoSaida, PromptAnterior: string;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  SecurityAttr: TSecurityAttributes;
  ReadPipe, WritePipe, NulHandle: THandle;
  Buffer: array[0..4095] of Byte;
  BytesRead, BytesDisponiveis, BytesParaLer, ExitCode, InicioTick: DWORD;
  OutputStream: TMemoryStream;
  OutputBytes: TBytes;
  ProcessoCriado, EstourouTempo: Boolean;
begin
  Result := '';
  CodigoSaidaUltimoGit := Cardinal(-1);
  if not GitCommandPermitido(Comando) then
  begin
    CodigoSaidaUltimoGit := 1;
    Result := 'Comando Git bloqueado: somente consulta, checkout local/remoto e pull --ff-only.';
    Exit;
  end;

  GitExe := IncludeTrailingPathDelimiter(LerCaminhoGitDoIni) + 'git.exe';
  if not FileExists(GitExe) then
  begin
    CodigoSaidaUltimoGit := 1;
    Result := 'Erro: git.exe nao foi encontrado em ' + GitExe;
    Exit;
  end;
  if not DirectoryExists(Pasta) then
  begin
    CodigoSaidaUltimoGit := 1;
    Result := 'Erro: pasta do repositorio nao existe: ' + Pasta;
    Exit;
  end;

  CommandLine := QuoteCommandLineArgument(GitExe);
  PuttyDir := Trim(LerCaminhoExePuTTYDoINI);
  PuttyKey := Trim(LerCaminhoPuTTYDoINI);
  if (PuttyDir <> '') or (PuttyKey <> '') then
  begin
    PlinkExe := TPath.Combine(PuttyDir, 'plink.exe');
    if (PuttyDir = '') or (PuttyKey = '') or not DirectoryExists(PuttyDir) or
       not FileExists(PlinkExe) or
       not FileExists(TPath.Combine(PuttyDir, 'pageant.exe')) or
       not FileExists(PuttyKey) or
       not SameText(ExtractFileExt(PuttyKey), '.ppk') then
    begin
      CodigoSaidaUltimoGit := 1;
      Result := 'Configuracao PuTTY incompleta ou invalida. Corrija ou desative PuTTY nas configuracoes.';
      Exit;
    end;

    SSHCommand := '"' + PlinkExe + '" -i "' + PuttyKey + '" -batch';
    CommandLine := CommandLine + ' -c ' +
      QuoteCommandLineArgument('core.sshCommand=' + SSHCommand);
  end;
  // Preserva credential helpers, SSH, GitHub CLI configurado como helper e HTTPS.
  CommandLine := CommandLine + ' -C ' + QuoteCommandLineArgument(Pasta) + ' ' + Comando;

  ReadPipe := 0;
  WritePipe := 0;
  NulHandle := INVALID_HANDLE_VALUE;
  ProcessoCriado := False;
  EstourouTempo := False;
  ZeroMemory(@SecurityAttr, SizeOf(SecurityAttr));
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @SecurityAttr, 0) then
  begin
    CodigoSaidaUltimoGit := GetLastError;
    Result := 'Erro ao criar canal de saida do Git: ' + SysErrorMessage(CodigoSaidaUltimoGit);
    Exit;
  end;

  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    NulHandle := CreateFile(PChar('NUL'), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
      @SecurityAttr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if NulHandle = INVALID_HANDLE_VALUE then
    begin
      CodigoSaidaUltimoGit := GetLastError;
      Result := 'Erro ao preparar entrada nao interativa do Git: ' + SysErrorMessage(CodigoSaidaUltimoGit);
      Exit;
    end;

    ZeroMemory(@StartupInfo, SizeOf(StartupInfo));
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.wShowWindow := SW_HIDE;
    StartupInfo.hStdOutput := WritePipe;
    StartupInfo.hStdError := WritePipe;
    StartupInfo.hStdInput := NulHandle;

    ZeroMemory(@ProcessInfo, SizeOf(ProcessInfo));
    UniqueString(CommandLine);
    PromptAnterior := GetEnvironmentVariable('GIT_TERMINAL_PROMPT');
    SetEnvironmentVariable(PChar('GIT_TERMINAL_PROMPT'), PChar('0'));
    try
      if not CreateProcess(nil, PChar(CommandLine), nil, nil, True,
        CREATE_NO_WINDOW, nil, nil, StartupInfo, ProcessInfo) then
      begin
        CodigoSaidaUltimoGit := GetLastError;
        Result := 'Erro ao iniciar Git: ' + SysErrorMessage(CodigoSaidaUltimoGit);
        Exit;
      end;
      ProcessoCriado := True;
    finally
      if PromptAnterior = '' then
        SetEnvironmentVariable(PChar('GIT_TERMINAL_PROMPT'), nil)
      else
        SetEnvironmentVariable(PChar('GIT_TERMINAL_PROMPT'), PChar(PromptAnterior));
    end;

    CloseHandle(WritePipe);
    WritePipe := 0;
    CloseHandle(NulHandle);
    NulHandle := INVALID_HANDLE_VALUE;
    OutputStream := TMemoryStream.Create;
    try
      InicioTick := GetTickCount;
      repeat
        if (GetTickCount - InicioTick) >= TEMPO_MAXIMO_GIT_MS then
        begin
          EstourouTempo := True;
          TerminateProcess(ProcessInfo.hProcess, 1);
          WaitForSingleObject(ProcessInfo.hProcess, 5000);
          Break;
        end;
        BytesDisponiveis := 0;
        if PeekNamedPipe(ReadPipe, nil, 0, nil, @BytesDisponiveis, nil) and
           (BytesDisponiveis > 0) then
        begin
          if BytesDisponiveis > SizeOf(Buffer) then
            BytesParaLer := SizeOf(Buffer)
          else
            BytesParaLer := BytesDisponiveis;
          if ReadFile(ReadPipe, Buffer, BytesParaLer, BytesRead, nil) and
             (BytesRead > 0) then
            OutputStream.WriteBuffer(Buffer, BytesRead);
        end
        else if WaitForSingleObject(ProcessInfo.hProcess, 50) = WAIT_OBJECT_0 then
          Break;
      until False;

      // Recolhe a saida que ainda estiver no pipe apos o encerramento.
      repeat
        BytesDisponiveis := 0;
        if not PeekNamedPipe(ReadPipe, nil, 0, nil, @BytesDisponiveis, nil) or
           (BytesDisponiveis = 0) then
          Break;
        if BytesDisponiveis > SizeOf(Buffer) then
          BytesParaLer := SizeOf(Buffer)
        else
          BytesParaLer := BytesDisponiveis;
        if not ReadFile(ReadPipe, Buffer, BytesParaLer, BytesRead, nil) or
           (BytesRead = 0) then
          Break;
        OutputStream.WriteBuffer(Buffer, BytesRead);
      until False;

      if not GetExitCodeProcess(ProcessInfo.hProcess, ExitCode) then
        ExitCode := GetLastError;
      if EstourouTempo then
        CodigoSaidaUltimoGit := 1
      else
        CodigoSaidaUltimoGit := ExitCode;

      if OutputStream.Size > 0 then
      begin
        SetLength(OutputBytes, OutputStream.Size);
        OutputStream.Position := 0;
        OutputStream.ReadBuffer(OutputBytes[0], Length(OutputBytes));
        TextoSaida := Trim(TEncoding.UTF8.GetString(OutputBytes));
      end
      else
        TextoSaida := '';

      if EstourouTempo then
        Result := 'O comando Git excedeu o limite de 30 minutos e foi encerrado para evitar bloqueio.'
      else if (CodigoSaidaUltimoGit <> 0) and (TextoSaida = '') then
        Result := Format('Git terminou com codigo %d sem retornar detalhes. Verifique autenticacao, rede e configuracao do repositorio.', [CodigoSaidaUltimoGit])
      else
        Result := TextoSaida;
    finally
      OutputStream.Free;
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
      ProcessoCriado := False;
    end;
  finally
    if ProcessoCriado then
    begin
      TerminateProcess(ProcessInfo.hProcess, 1);
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end;
    if NulHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(NulHandle);
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
    if ReadPipe <> 0 then
      CloseHandle(ReadPipe);
  end;

  if ArquivoLogGlobal <> '' then
    TFile.AppendAllText(ArquivoLogGlobal,
      Format('[%s] git -C "%s" %s (exit %d)%s%s%s',
        [DateTimeToStr(Now), Pasta, Comando, CodigoSaidaUltimoGit,
         sLineBreak, Result, sLineBreak]), TEncoding.UTF8);
end;
function ExecutarComandoGitSSH(const Comando, Pasta: string): string;
begin
  Result := ExecutarComandoGit(Comando, Pasta);
end;

function ExecutarComandoGitSSHComEnv(const Comando, Pasta: string): string;
begin
  SSHAuthSock := GetSSHAuthSock;
  Result := ExecutarComandoGit(Comando, Pasta);
end;

function BranchAtual(const Pasta: string; Exec: TGitExecutor): string;
begin
  Result := Trim(Exec('rev-parse --abbrev-ref HEAD', Pasta));
end;

function BranchExiste(const Pasta, Branch: string; Exec: TGitExecutor): Boolean;
var
  Resultado, BranchNormalizada, Linha: string;
  Linhas: TArray<string>;
begin
  BranchNormalizada := Branch;

  Resultado := Exec('branch --list --format="%(refname:short)"', Pasta);
  Linhas := Resultado.Split([sLineBreak]);
  Result := False;
  for Linha in Linhas do
    if Trim(Linha) = BranchNormalizada then
      Exit(True);
end;

function BranchRemotaExiste(const Pasta, Branch: string; Exec: TGitExecutor): Boolean;
var
  Resultado, Linha: string;
  Linhas: TArray<string>;
begin
  Resultado := Exec('for-each-ref --format="%(refname:short)" refs/remotes', Pasta);
  Linhas := Resultado.Split([sLineBreak]);
  Result := False;
  for Linha in Linhas do
    if Trim(Linha) = Branch then
      Exit(True);
end;
function HaAlteracoesPendentes(const Pasta: string; Exec: TGitExecutor): Boolean;
var
  Resultado: string;
  Linhas: TArray<string>;
  Linha: string;
  AlteracaoValida: Boolean;
begin
  Resultado := Trim(Exec('status --porcelain', Pasta));
  if CodigoSaidaUltimoGit <> 0 then
    Exit(True);
  Result := False;

  if Resultado = '' then
    Exit(False);

  // Verifica se há linhas com alteração real (ex: começa com " M", "??", etc)
  AlteracaoValida := False;
  Linhas := Resultado.Split([sLineBreak]);
  for Linha in Linhas do
  begin
    var LinhaTrim := Trim(Linha);
    if (Length(LinhaTrim) >= 2) and
       ((LinhaTrim[1] in [' ', 'M', 'A', 'D', '?']) or (LinhaTrim[1] = '?')) then
    begin
      AlteracaoValida := True;
      Break;
    end;
  end;

  Result := AlteracaoValida;

  if Result then
    FGerenciadorDePastas.AdicionarLogNaTela('Alterações pendentes detectadas:' + sLineBreak + Resultado)

end;


end.

