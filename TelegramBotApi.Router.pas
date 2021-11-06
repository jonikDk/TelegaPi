﻿unit TelegramBotApi.Router;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  TelegramBotApi.Types;

type
  // Управление текущим состоянием пользователя
  TtgRouteUserStateManagerAbstract = class abstract
  private
    FOnGetUserStateCallback: TFunc<Int64, string>;
    FOnSetUserStateCallback: TProc<Int64, string>;
    FDefaultName: string;
  protected
    function DoGetUserState(const AUserID: Int64): string; virtual;
    procedure DoSetUserState(const AIndex: Int64; const Value: string); virtual;
  public
    constructor Create; virtual;
    // имя "нулевого" маршрута
    property DefaultName: string read FDefaultName write FDefaultName;
    // Класс запрашивает из сторонего хранилища состояние пользователя по ИД пользователя
    property OnGetUserStateCallback: TFunc<Int64, string> read FOnGetUserStateCallback write FOnGetUserStateCallback;
    // класс сообщает что для пользователя установлено новое состояние
    property OnSetUserStateCallback: TProc<Int64, string> read FOnSetUserStateCallback write FOnSetUserStateCallback;
    // Чтение/Запись состояний
    property UserState[const AIndex: Int64]: string read DoGetUserState write DoSetUserState;
  end;

  // Хранение состояний в ОЗУ. Для начала неплохой вариант.
  // Не забывать сохранять/загружать актуальные состояния в постоянную память (на диск)
  // Потом написать класс для хранения состояний в БД что бы не переживать за аварийное завершение бота
  TtgRouteUserStateManagerRAM = class(TtgRouteUserStateManagerAbstract)
  private
    FRouteUserStates: TDictionary<Int64, string>;
  protected
    function DoGetUserState(const AUserID: Int64): string; override;
    procedure DoSetUserState(const AIndex: Int64; const Value: string); override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  // Точка маршрута
  TtgRoute = record
  private
    FName: string;
    FOnStartCallback: TProc<TtgMessage>;
    FOnMessageCallback: TProc<TtgMessage>;
    FOnStopCallback: TProc<TtgMessage>;
    // protected
    procedure RouteStart(AMessage: TtgMessage);
    procedure RouteStop(AMessage: TtgMessage);
    procedure SendMessage(AMessage: TtgMessage);
  public
    class function Create(const AName: string): TtgRoute; static;
    // Имя точки.
    // Возможно, по имени точки будет происходить переход на нужныый маршрут
    property Name: string read FName write FName;
    // Отправляем побуждение к действию
    property OnStartCallback: TProc<TtgMessage> read FOnStartCallback write FOnStartCallback;
    // Обрабатывапем ответ от пользователя
    property OnMessageCallback: TProc<TtgMessage> read FOnMessageCallback write FOnMessageCallback;
    // вызывается при перемещении на следующую точку маршрута. Возможно, лишний колбек.
    property OnStopCallback: TProc<TtgMessage> read FOnStopCallback write FOnStopCallback;
  end;

  // Управление маршрутами
  TtgRouteManager = class
  private
    FRouteUserState: TtgRouteUserStateManagerAbstract;
    FRoutes: TDictionary<string, TtgRoute>;
    FOnRouteNotFound: TProc<Int64, string>;
  protected
    procedure DoNotifyRouteNotFound(const AId: Int64; const ARouteName: string);
    procedure DoCheckRouteIsExist(const AId: Int64; const ARouteName: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure MoveTo(const AUserID: Int64; const ARouteName: string);
    // регистрируем точку
    procedure RegisterRoute(ARoute: TtgRoute);
    // регистрируем точки
    procedure RegisterRoutes(ARoutes: TArray<TtgRoute>);
    // Уведомляем маршрутизатор о новом сообщении
    procedure SendMessage(AMessage: TtgMessage);
    // property Routes: TDictionary<string, TtgRoute> read FRoutes write FRoutes;
    // Доступ к состояниям пользователей
    property RouteUserState: TtgRouteUserStateManagerAbstract read FRouteUserState write FRouteUserState;
    // Колбек перехода на несуществующий маршрут
    property OnRouteNotFound: TProc<Int64, string> read FOnRouteNotFound write FOnRouteNotFound;
  end;

implementation

{ TtgRouteUserStateManagerAbstract }

constructor TtgRouteUserStateManagerAbstract.Create;
begin
  FDefaultName := '/start';
end;

function TtgRouteUserStateManagerAbstract.DoGetUserState(const AUserID: Int64): string;
begin
  if Assigned(FOnGetUserStateCallback) then
    Result := FOnGetUserStateCallback(AUserID);
  // if Result.IsEmpty then
  // Result := FDefaultName;
end;

procedure TtgRouteUserStateManagerAbstract.DoSetUserState(const AIndex: Int64; const Value: string);
begin
  if Assigned(OnSetUserStateCallback) then
    OnSetUserStateCallback(AIndex, Value);
end;

{ TtgRouteUserStateManagerRAM }

constructor TtgRouteUserStateManagerRAM.Create;
begin
  inherited Create();
  FRouteUserStates := TDictionary<Int64, string>.Create;
end;

destructor TtgRouteUserStateManagerRAM.Destroy;
begin
  FRouteUserStates.Free;
  inherited Destroy;
end;

function TtgRouteUserStateManagerRAM.DoGetUserState(const AUserID: Int64): string;
begin
  // inherited DoGetUserState(AUserID);
  if not FRouteUserStates.TryGetValue(AUserID, Result) then
    Result := FDefaultName;

end;

procedure TtgRouteUserStateManagerRAM.DoSetUserState(const AIndex: Int64; const Value: string);
begin
  inherited DoSetUserState(AIndex, Value);
  FRouteUserStates.AddOrSetValue(AIndex, Value);
end;

{ TtgRoute }

class function TtgRoute.Create(const AName: string): TtgRoute;
begin
  Result.Name := AName;
end;

procedure TtgRoute.RouteStart(AMessage: TtgMessage);
begin
  if Assigned(OnStartCallback) then
    OnStartCallback(AMessage);
end;

procedure TtgRoute.RouteStop(AMessage: TtgMessage);
begin
  if Assigned(OnStopCallback) then
    OnStopCallback(AMessage);
end;

procedure TtgRoute.SendMessage(AMessage: TtgMessage);
begin
  if Assigned(OnMessageCallback) then
    OnMessageCallback(AMessage);
end;

{ TtgRouteManager }

constructor TtgRouteManager.Create;
begin
  FRoutes := TDictionary<string, TtgRoute>.Create;
end;

destructor TtgRouteManager.Destroy;
begin
  FRoutes.Free;
  inherited;
end;

procedure TtgRouteManager.DoCheckRouteIsExist(const AId: Int64; const ARouteName: string);
begin
  if not FRoutes.ContainsKey(ARouteName) then
    DoNotifyRouteNotFound(AId, ARouteName);
end;

procedure TtgRouteManager.DoNotifyRouteNotFound(const AId: Int64; const ARouteName: string);
begin
  if Assigned(FOnRouteNotFound) then
    FOnRouteNotFound(AId, ARouteName)
  else
    raise Exception.CreateFmt('Route "%s" for UserID "%d" not found', [ARouteName, AId]);
end;

procedure TtgRouteManager.MoveTo(const AUserID: Int64; const ARouteName: string);
begin
  FRouteUserState.UserState[AUserID] := ARouteName;
end;

procedure TtgRouteManager.RegisterRoute(ARoute: TtgRoute);
begin
  FRoutes.AddOrSetValue(ARoute.Name, ARoute);
end;

procedure TtgRouteManager.RegisterRoutes(ARoutes: TArray<TtgRoute>);
var
  I: Integer;
begin
  for I := Low(ARoutes) to High(ARoutes) do
    RegisterRoute(ARoutes[I]);
end;

procedure TtgRouteManager.SendMessage(AMessage: TtgMessage);
var
  LRoute: TtgRoute;
  lCurrentUserID: Int64;
  LCurrentState: string;
begin
  lCurrentUserID := AMessage.Chat.ID;
  LCurrentState := FRouteUserState.UserState[lCurrentUserID];
  DoCheckRouteIsExist(lCurrentUserID, LCurrentState);
  if FRoutes.TryGetValue(LCurrentState, LRoute) then
  begin
    LRoute.SendMessage(AMessage);
  end;

end;

end.
