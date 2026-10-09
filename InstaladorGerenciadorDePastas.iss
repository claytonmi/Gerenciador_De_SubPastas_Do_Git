#define AppName "Gerenciador de Pastas do Git"
#define AppVersion "1.0.0"
#define AppExeName "GerenciadorDePastas.exe"
#define AppIconName "GerenciadorDePastas_Icon.ico"

[Setup]
AppId={{16CA7A19-F281-47C7-97E4-E76E35B0DC3C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Gerenciador de Pastas do Git
DefaultDirName={localappdata}\Programs\GerenciadorDePastasDoGit
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Download
OutputBaseFilename=GerenciadorDePastasDoGit-Setup
SetupIconFile={#AppIconName}
UninstallDisplayIcon={app}\{#AppIconName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x86 x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"; Flags: unchecked

[Files]
; Compile o projeto Delphi em Win32 e Win64 (Debug) antes de gerar o instalador.
; Em Windows 64 bits, o usuário escolhe qual executável instalar.
Source: "Win32\Debug\GerenciadorDePastas.exe"; DestDir: "{app}"; DestName: "{#AppExeName}"; Flags: ignoreversion; Check: not Is64BitSelected
Source: "Win64\Debug\GerenciadorDePastas.exe"; DestDir: "{app}"; DestName: "{#AppExeName}"; Flags: ignoreversion; Check: Is64BitSelected
Source: "Win32\Debug\libeay32.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: not Is64BitSelected
Source: "Win32\Debug\ssleay32.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: not Is64BitSelected
Source: "Win64\Debug\libeay32.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: Is64BitSelected
Source: "Win64\Debug\ssleay32.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: Is64BitSelected
Source: "Doc\GuiaDeUsuario.pdf"; DestDir: "{app}\Doc"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppIconName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppIconName}"; IconIndex: 0
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppIconName}"; IconIndex: 0; Tasks: desktopicon

[Registry]
; Menu de contexto por usuário; a chave é removida ao desinstalar.
Root: HKCU; Subkey: "Software\Classes\Directory\shell\GerenciadorDePastasGit"; ValueType: string; ValueName: ""; ValueData: "Abrir Gerenciador de Pastas Git"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\GerenciadorDePastasGit"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppIconName}"
Root: HKCU; Subkey: "Software\Classes\Directory\shell\GerenciadorDePastasGit\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName}"; Flags: postinstall nowait skipifsilent
[Code]
var
  ArchitecturePage: TInputOptionWizardPage;

function Is64BitSelected: Boolean;
begin
  Result := IsWin64 and (ArchitecturePage.SelectedValueIndex = 1);
end;

procedure InitializeWizard;
begin
  ArchitecturePage := CreateInputOptionPage(wpSelectDir,
    'Versão do aplicativo', 'Escolha a arquitetura',
    'Selecione a versão que deseja instalar:', True, False);
  ArchitecturePage.Add('32 bits (compatível com Windows 32 e 64 bits)');
  ArchitecturePage.Add('64 bits (somente Windows 64 bits)');
  ArchitecturePage.SelectedValueIndex := Ord(IsWin64);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ArchitecturePage.ID) and not IsWin64;
end;
