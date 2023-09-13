// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
contract FingerGuess is Ownable{

    struct Game{
        address sponsor; //游戏发起者
        address defier; //挑战者
        address tokenAddress; //token合约地址， 为0则代表是原生币.
        uint256 bonus; //游戏奖金
        uint256 gameType;// 游戏类型 0:普通猜拳，1:三局两胜
        uint256 status; //游戏状态 0:可匹配，1：已关闭，2:已完成
        uint256 createTime; //创建时间
    }
    
    enum FingerType{None,Scissor,Stone,Cloth} //猜拳类型，none, 剪刀、石头、布 其中none为占位符，因为solidity里不允许有空值
    mapping(uint256 =>FingerType[]) guessResult;  //每局竞猜结果.  这里设计，数组前三为游戏发起者的猜拳，后三位为挑战者的猜拳
    uint256 feeRate = 5; //手续费  百分比
    address feeAddress; // 接收手续费转账的地址
    Game[] games;
    // Game[] finishedGames;
    // mapping(address => Game[]) playerGames; //用户参与的游戏
    event StartGame(address indexed  sponser,address indexed tokenAddress,uint256 gameId, uint256 bonus); //开一场游戏事件
    event Ruling(address indexed  sponser,address indexed defier,uint256 gameId, uint256 result ,uint256 bonus); //裁定结果

    //开始一局游戏
    function startGame(address _tokenAddress, uint256 _bonus,uint256 _gameType,FingerType[] calldata _guessResult)external payable gameChecker(_tokenAddress,_bonus,_gameType,_guessResult) {
        Game memory _game = Game({
            sponsor: msg.sender,
            defier: address(0),
            tokenAddress: _tokenAddress,
            bonus: _tokenAddress == address(0) ? msg.value : _bonus,
            gameType: _gameType,
            status: 0,
            createTime: block.timestamp
       } );
       games.push(_game); //添加到游戏数组
       FingerType[6] memory fingers;
       fingers[0] = _guessResult[0];
       fingers[1] = _guessResult[1];
       fingers[2] = _guessResult[2];
       guessResult[games.length-1] = fingers; //猜拳结果对应到游戏id上

       reciveToken(games[games.length - 1]); //如果是第三方代币，需要转到合约里

       emit StartGame(msg.sender, _tokenAddress, games.length-1, _bonus);
    }
    //检查猜拳结果
    function checkFingerGuess(uint256 _gameType, FingerType[] calldata _guessResult)internal pure returns ( bool ) {
        require(_gameType == 0 || _gameType == 1, "Guess type error");
        bool _result = true;
        if(_gameType == 0){
            _result = _guessResult[0] == FingerType.Scissor || _guessResult[0] == FingerType.Stone || _guessResult[0] == FingerType.Cloth;
        }
        if(_gameType == 1){
            for(uint256 i=0;i<3;i++){
                _result = _guessResult[i] == FingerType.Scissor || _guessResult[i] == FingerType.Stone || _guessResult[i] == FingerType.Cloth;
                if(!_result){
                    break;
                }
            }
        }
        return _result;
       
    }
    //合约接收token
    function reciveToken(Game storage _game)internal {
        //非0地址，所以需要new erc20对象转账
        if(_game.tokenAddress != address(0)){
            ERC20 token = ERC20(_game.tokenAddress);
            uint256 _decimal = token.decimals();
            uint256 amount = _game.bonus * 10 **_decimal;
            _game.bonus = amount;
            token.transferFrom(msg.sender, address(this), amount);
        }
    }
    //加入一个游戏
    function joinGame(uint256 _gameId, FingerType[] calldata _guessResult)external payable {
        Game storage _game = games[_gameId];
        require(_game.sponsor != address(0), "Game not exists");
        require(_game.status == 0, "Game has been over");
        require(checkFingerGuess(_game.gameType, _guessResult), "Guessing error" );
        //存储猜拳结果
        FingerType[] storage fingers = guessResult[_gameId];
        fingers[3] = _guessResult[0];
        fingers[4] = _guessResult[1];
        fingers[5] = _guessResult[2];
        if(_game.tokenAddress == address(0)){
            require(msg.value >= _game.bonus, "Insufficient amount");
        }else{
            ERC20 token = ERC20(_game.tokenAddress);
            token.transferFrom(msg.sender, address(this), _game.bonus);
        }
        _game.defier = msg.sender;
        // //比较猜拳输赢
        compareLogic(_game, _gameId, fingers);
        
    }
    //猜拳
    function compareLogic(Game storage _game, uint256 _gameId, FingerType[] storage _guessResult )internal {
        uint256 _result = 0;
        //普通猜拳
        if(_game.gameType == 0){
            _result = guessLogic(_guessResult[0], _guessResult[3]);
        }else{
            uint256 _a = 0;
            uint256 _b = 0;
            //三局两胜 最少要比较两次
            for(uint256 i=0;i<3;i++){
                 _result = guessLogic(_guessResult[i], _guessResult[i+3]);
                 if(_result == 1){
                     _a+=1;
                 }else if(_result == 1){
                     _b+=1;
                 }
            }
            if(_a == _b){
                _result == 0;
            }else if(_a > _b){
                _result == 1;
            }else{
                _result == 2;
            }
        }
        sendToken(_game, _gameId, _result);
    }
    //游戏完成，转帐逻辑
    function sendToken(Game storage _game, uint256 _gameId, uint256 _result)internal {
         uint256 _singleFee = _game.bonus * feeRate / 100; //手续费 单边
        //原生转账
        if(_game.tokenAddress == address(0)){
            //平局
            if(_result == 0){
                payable(_game.sponsor).transfer(_game.bonus - _singleFee);
                payable(_game.defier).transfer(_game.bonus - _singleFee);
            }else if(_result == 1){//发起者胜利
                payable(_game.sponsor).transfer(_game.bonus * 2 - _singleFee * 2);
            }else{//竞猜者胜利
                 payable(_game.defier).transfer(_game.bonus * 2 - _singleFee * 2);
            }
            //转出手续费
            if(feeAddress != address(0)){
                payable(feeAddress).transfer( _singleFee * 2);
            }
        }else{
            ERC20 token = ERC20(_game.tokenAddress);

            //平局
            if(_result == 0){
                token.transfer(_game.sponsor, _game.bonus - _singleFee);
                token.transfer(_game.defier, _game.bonus - _singleFee);
            }else if(_result == 1){//发起者胜利
                 token.transfer(_game.sponsor, _game.bonus * 2 - _singleFee * 2);
            }else{//竞猜者胜利
                token.transfer(_game.defier, _game.bonus * 2 - _singleFee * 2);
            }
            //转出手续费
            if(feeAddress != address(0)){
                token.transfer(feeAddress, _singleFee * 2);
            }
        }
        _game.status = 2;
        //已完成游戏存储
        // finishedGames.push(_game);

        // //从数组中删除已完成游戏
        // games[_gameId] = games[games.length - 1];
        // games.pop();
        // Game memory fGame = finishedGames[finishedGames.length - 1];
        // Game[] storage sponsorGames = playerGames[fGame.sponsor];
        // Game[] storage defierGames = playerGames[_game.defier];
        // defierGames.push(_game); //存储用户对应的游戏
        // defierGames.push(fGame);
        // emit Ruling(fGame.sponsor, fGame.defier, _gameId, _result, fGame.bonus);
        emit Ruling(_game.sponsor, _game.defier, _gameId, _result, _game.bonus);
    }
    function guessLogic(FingerType a, FingerType b)internal pure returns (uint256){
        if(a == b){
            return 0; //平局
        }else if ((a == FingerType.Scissor && b == FingerType.Cloth) || (a == FingerType.Stone && b == FingerType.Scissor) || (a == FingerType.Cloth && b == FingerType.Stone)){
            return 1; //发起者胜利
        }else{
            return 2; //竞猜者胜利
        }
    }
    function getFingers(uint256 _gameId)external view returns (FingerType[] memory){
        FingerType[] storage fingers = guessResult[_gameId];
        return fingers;
    }
   function getGame(uint256 _gameId)external view returns (Game memory game){
       game = games[_gameId];
    }
    function test()external view returns (address){
        return msg.sender;
    }

    function getGamesByPage(uint256 pageNum, uint256 pageSize) public view returns (Game[] memory) {
        require(pageNum > 0 && pageSize > 0, "Invalid pageNum or pageSize");
        
        uint256 startIndex = (pageNum - 1) * pageSize;
        uint256 endIndex = startIndex + pageSize;
        
        if (startIndex >= games.length) {
            // 如果起始索引超出了数组范围，返回空数组
            return new Game[](0);
        }
        
        if (endIndex > games.length) {
            endIndex = games.length;
        }
        
        Game[] memory result = new Game[](endIndex - startIndex);
        
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = games[i];
        }
        
        return result;
    }


    //开始游戏校验
    modifier gameChecker(address _tokenAddress, uint256 _bonus,uint256 _gameType,FingerType[] calldata _guessResult){
        require((_tokenAddress != address(0) && _bonus > 0) || (_tokenAddress == address(0) && msg.value >0 ),"Game bonus cannot be zero");
        //如果是普通猜拳，那么_guessResult[0] 必须不能为 0，因为 solidity里 0 是默认值
        //如果是普通猜拳，那么_guessResult[0][1][2] 必须不能为 0
        require((_gameType == 0 || _gameType == 1) && checkFingerGuess(_gameType, _guessResult), "Guessing error" );

        _;
    }


}