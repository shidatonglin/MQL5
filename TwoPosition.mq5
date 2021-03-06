//+------------------------------------------------------------------+
//|                                                    MakeMoney.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//双仓EA(一单买入，一单卖出) 
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\AccountInfo.mqh>//账户信息
#include <Trade\DealInfo.mqh>//交易类 只针对已经发生了交易的
#include <Trade\HistoryOrderInfo.mqh>//历史订单，可能包括没有交易成功的订单
#include <Trade\OrderInfo.mqh>//订单类
#include <Trade\SymbolInfo.mqh>//货币基础类
#include <Trade\PositionInfo.mqh>//仓位
#include <Trade\Trade.mqh>//交易类
//#include <..\Experts\makemoney\MyTradeObject.mqh>//我的交易类
#include <..\Experts\Examples\MQL5\MyTradeObject.mqh>//我的交易类
CMyTradeObject buyObject;//买入对象
CMyTradeObject sellObject;//卖出对象
                          //创建基本对象
CPositionInfo     myPosition;  //持仓对象
CSymbolInfo mySymbol;//品种(货币)对象
CAccountInfo myAccount;//账户对象
CHistoryOrderInfo myHistoryOrderInfo;//历史交易订单对象
CTrade myTrade;//交易对象
CDealInfo myDealInfo;//已经交易的订单对象（已经交易）
double everyLots=1;//每次交易的手数
double lastMinutePrice=0;//最近一次整分钟点的价格（时时最新）初始是0
double mvLastMinutePrice=0;//最近一次整分钟点的价格（mvTimes日移动平均线）Moving Average 初始是0
static int TRADE_SIGNAL_BUY=1;//买入信号
static int TRADE_SIGNAL_SELL=0;//卖出信号
static int TRADE_SIGNAL_NONE=-1;//非交易信号
int mvTimes=25;//移动平均线的频率 25天
int compareStatus=0;//mvTimes日均线价格和最新价格比较状态
                    // 0:mvTimes日均价大于最新价格 1:mvTimes.。小于最新价格
int initDealCount=10;//第一次交易等待数据初始化的时间
int POSITION_MAX=2; //允许开仓的最大数量
static int POSITION_STATUS_S =0;//合适的仓位
static int POSITION_STATUS_L =1;//仓位过多
static double minProfit=20;//最小要赚的利润点数
static double maxLoss=-300;//当仓最大亏损大概点数
static double maxTradeDifference= 20;//最大的交易差值，在出现交易信号的时候使用
static double minTradeDifference = 3;//最小的交易差值，在出现交易信号的时候使用
static long bugMagicCode = 666666;
static long sellMagicCode = 888888;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//进行初始化前的安全校验
   bool check=checkInitTrade();
   if(!check)
     {
      printf("校验没有通过,不可以交易!!");
      return(INIT_FAILED);
     }
//初始化第一次的数据
   initMinutePrice();
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 先获取当前是都有仓位，如果没有，那么在价格发生交叉的时候先开一单。(暂时不考虑线程同步的问题)                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
// PositionSelect(_Symbol);//将服务器的数据写入本地缓存
   checkPositon();
   int tradeSignal=getTradeSignal();
//可以交易状态
   if(tradeSignal==TRADE_SIGNAL_BUY || tradeSignal==TRADE_SIGNAL_SELL)
     {
      openPosition(tradeSignal);
     }
//getPositionProfit();
   timeExchange();//调用时间往前函数
  }
//+------------------------------------------------------------------+
//|开仓|
//+------------------------------------------------------------------+
void  openPosition(int tradeSignal)
  {
   PositionSelect(_Symbol);
   int positionTotal=PositionsTotal();//获取当前仓位数量
   if(positionTotal==0)
     {
      //当前仓位是0  可以直接开一仓
      if(tradeSignal==TRADE_SIGNAL_BUY)
        {
          myTrade.Buy(everyLots,_Symbol);
            setTradeBuyObject(myTrade.ResultRetcode(),myTrade.ResultOrder(),myTrade.ResultPrice());
           }else if(tradeSignal==TRADE_SIGNAL_SELL){
          myTrade.Sell(everyLots,_Symbol);     
            setTradeSellObject(myTrade.ResultRetcode(),myTrade.ResultOrder(),myTrade.ResultPrice());         
        }
        }else if(positionTotal==1){ //如果已经开有一单的情况, 先判断这一单的利润，如果这一单的利润不错，那么就平仓了
      ulong ticket=PositionGetTicket(0);
      myPosition.SelectByTicket(ticket);
      double positionProfit=myPosition.Profit();//这一仓的利润
                                                //持仓类型和交易信号相反 意味着要考虑这一仓的利润 随时平仓了
      if((myPosition.PositionType()==POSITION_TYPE_BUY && tradeSignal==TRADE_SIGNAL_SELL) ||
         (myPosition.PositionType()==POSITION_TYPE_SELL && tradeSignal==TRADE_SIGNAL_BUY))
        {
         if(positionProfit>=minProfit)
           {
            //利润不错 可以平仓
                myTrade.PositionClose(ticket,0);
            uint resultCode=myTrade.ResultRetcode();
            if(resultCode!=TRADE_RETCODE_DONE)//完成交易返回值
              {
               printf("平仓失败,返回码是："+IntegerToString(resultCode));
                 }else{
               printf("平仓成功，利润为----"+DoubleToString(positionProfit));
              }
           }else if(positionProfit<=maxLoss){
            //亏损太多需要开对等仓
            if(myPosition.PositionType()==POSITION_TYPE_BUY && tradeSignal==TRADE_SIGNAL_SELL)
              {
                 myTrade.Sell(everyLots,_Symbol);
                  setTradeSellObject(myTrade.ResultRetcode(),myTrade.ResultOrder(),myTrade.ResultPrice());
                 }else if(myPosition.PositionType()==POSITION_TYPE_SELL && tradeSignal==TRADE_SIGNAL_BUY){
                 myTrade.Buy(everyLots,_Symbol);
                  setTradeBuyObject(myTrade.ResultRetcode(),myTrade.ResultOrder(),myTrade.ResultPrice());
              }
           }
        }
        }else if(positionTotal==2){
      printf("已经开了两仓了，不能再开仓了！！！");
        }else{
      checkPositon();
     }

  }
//设置 买入信息
void setTradeBuyObject(int result_code  ,ulong orderTicket,double price)
  {
  if(result_code == TRADE_RETCODE_DONE){
   buyObject.SetTicket(orderTicket);
   buyObject.SetMagic(bugMagicCode);//买入魔术号
   buyObject.SetPrice(price);
   buyObject.SetTime(TimeCurrent());
   }
  }
//设置卖空信息
void setTradeSellObject(int result_code,ulong orderTicket,double price)
  {
    if(result_code == TRADE_RETCODE_DONE){
      sellObject.SetTicket(orderTicket);
   sellObject.SetMagic(sellMagicCode);//卖出魔术号 
   sellObject.SetPrice(orderTicket);
   sellObject.SetTime(TimeCurrent());
    }
  }
//如果仓位过多
int checkPositon()
  {

//获取开仓总数,每一个未平仓的交易都是一个仓位。所以手中有多少没有平仓的交易就是多少个仓
   int positionTotal=PositionsTotal();
   if(positionTotal>POSITION_MAX)
     {//手中有还没有平仓的交易
      printf("持仓过多，将会平掉所有的仓，并退出程序！！！");
      for(int i=0;i<positionTotal;i++)
        {
         ulong ticket=PositionGetTicket(i);
         myTrade.PositionClose(ticket,0);
         uint resultCode=myTrade.ResultRetcode();
         if(resultCode!=TRADE_RETCODE_DONE)
           {
            printf("平仓失败,返回码是："+IntegerToString(resultCode));
           }
        }
      ExpertRemove();//退出程序
                     //不能直接返回成功的标识，可能有会一些交易被拒绝，平仓失败，所以需要等下一个刷新验证

      return POSITION_STATUS_L;//不能交易标识
        }else{
      return POSITION_STATUS_S;//合理的可以交易
     }
  }
//+------------------------------------------------------------------+
//获取交易信号 TRADE_SIGNAL_BUY   TRADE_SIGNAL_SELL   TRADE_SIGNAL_NONE
int getTradeSignal()
  {
   double nowTimePrice=getNowtimeMinutePrice();//时时价格
   double movingAverageMinutePrice=getMovingAverageMinutePirce();//移动平均线时时分钟价格
                                                                 //时间往前推进了一分钟 即当前最新的价格和上一次保存的分钟价格已经不一样了
  
      double signalProfit=(nowTimePrice-movingAverageMinutePrice)*1000;
         //判断应该买入还是卖出
         printf("差值为："+DoubleToString(signalProfit));
   if(lastMinutePrice!=nowTimePrice && mvLastMinutePrice!=movingAverageMinutePrice)
     {
      //判断在时间往前推进一分钟的同时，移动平均线和时时价格曲线是否出现了交叉，如果出现了交叉，则出现了交易信号
      if((lastMinutePrice>mvLastMinutePrice && nowTimePrice<movingAverageMinutePrice)
         || (lastMinutePrice<mvLastMinutePrice && nowTimePrice>movingAverageMinutePrice))
        {
         double signalProfit=(nowTimePrice-movingAverageMinutePrice)*1000;
         //判断应该买入还是卖出
         printf("差值为："+DoubleToString(signalProfit));
         if(signalProfit>=minTradeDifference && signalProfit<=maxTradeDifference)
           {

            return TRADE_SIGNAL_BUY;//买入 时时价格变为在上方
           }
         else if(signalProfit<=-minTradeDifference && signalProfit>=-maxTradeDifference)
           {//卖出 时时价格变为在下方
            return TRADE_SIGNAL_SELL;
           }
           }else {
         return TRADE_SIGNAL_NONE;
        }
     }
   return TRADE_SIGNAL_NONE;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+---------------------  //时间交换,往前推进一分钟---------------------------------------------+
void timeExchange()
  {
   double nowTimePrice=getNowtimeMinutePrice();
   double movingAverageMinutePrice=getMovingAverageMinutePirce();
   if(movingAverageMinutePrice!=mvLastMinutePrice && lastMinutePrice!=nowTimePrice)
     {
      lastMinutePrice=nowTimePrice;
      mvLastMinutePrice=movingAverageMinutePrice;
     }
  }
//+--------------------------获取MovingAverage分钟价格----------------------------------------+
double getMovingAverageMinutePirce()
  {
//每分钟 mvTimes 均线
   int mvMinutePrice=iMA(Symbol(),PERIOD_M1,mvTimes,0,MODE_SMA,PRICE_CLOSE);
   double mvMinutePriceList[];//分钟价格
   ArraySetAsSeries(mvMinutePriceList,true);
   CopyBuffer(mvMinutePrice,0,0,2,mvMinutePriceList);
//初始化第一分钟价格 mv
   return mvMinutePriceList[1];
  }
//+----------------------------获取nowTimeMinute分钟价格--------------------------------------+
double getNowtimeMinutePrice()
  {
//实时价格
   int nowMinutePrice=iMA(Symbol(),0,1,0,MODE_SMA,PRICE_CLOSE);
   double nowMinutePriceList[];//时时价格
   ArraySetAsSeries(nowMinutePriceList,true);
   CopyBuffer(nowMinutePrice,0,0,2,nowMinutePriceList);
//1为 上一分钟价格  0 为时时价格
   return nowMinutePriceList[1];//初始化第一分钟价格 now
  }
//初始化价格 只有初始化的时候调用
void initMinutePrice()
  {
   mvLastMinutePrice=getMovingAverageMinutePirce();
   lastMinutePrice=getNowtimeMinutePrice();
   printf("初始化价格成功："+TimeToString(TimeCurrent())+";---nowTimeMinute价格："
          +DoubleToString(lastMinutePrice)+";---movingAverageMinute价格："+DoubleToString(mvLastMinutePrice));
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//检查当前是否可以交易（仅仅用在初始化的时候）
bool checkInitTrade()
  {
//查看当前交易品种
   if(!mySymbol.Name("EURUSD"))
     {
      printf("当前品种不是EURUSD,不进行交易！！！");
      return false;
     }
//查看当前账号
//long  accountId = 7345113 ;
   const long   accountId=8436620;
   printf("当前交易账户："+myAccount.Login());
   if(myAccount.Login()!=accountId)
     {
      //   printf("当前登录账号不对,不能进行交易！！！");
      //  return false;
     }
//查看当前交易模式
   if(myAccount.TradeMode()!=ACCOUNT_TRADE_MODE_DEMO)
     {
      printf("当前账号交易模式不是模拟账户,不进行交易！！！");
      return false;
     }
//确保是线程安全！！！！
   if(!myAccount.TradeAllowed() || !myAccount.TradeExpert() || !mySymbol.IsSynchronized())
     {
      printf("账户异常,不能交易！！！");
      return false;
     }
   int ordersTotal=OrdersTotal();//当前挂单量
   if(ordersTotal>0)
     {
      printf("当前账户有未完成的订单，不能继续交易！！");
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
