pragma solidity ^0.5.10;

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/math/SafeMath.sol";
import "./Ownable.sol";

interface ITokenRewardPool {
    //스테이킹
    function stake (address account, uint256 amount) external returns (bool);

    //스테이킹 취소
    function Unstake (address account) external returns (bool);

    //이자만 출금
    function claimReward (address account) external returns (bool);

    //긴급 출금
    function emergencyTokenExit (address account) external returns (bool);

   //전체 스테이킹 양
    function totalStakedAmount() external view returns (uint256);

    //계정당 스테이킹 양 확인
    function stakedAmount(address account) external view returns (uint256);

    //계정당 리워드 양 확인
    function rewardAmount(address account) external view returns (uint256);

    //시작한 리워드 양
    function beginRewardAmount() external view returns (uint256);

    //남아 있는 리워드 양
    function remainRewardAmount() external view returns (uint256);
	
    //연간 이율 확인
    function ratePool() external view returns (uint256);

    //풀이 동작상태인지 확인
    function IsRunningPool() external view returns (bool);

}

contract TokenRewardPool is ITokenRewardPool{
    using SafeMath for uint256;
    bool private IS_RUNNING_POOL;

    uint256 private TOTAL_STAKED_AMOUNT; //현재 스테이킹양
    uint256 private BEGIN_REWARD; //초기 등록된 전체 리워드양
    uint256 private REMAIN_REWARD; //남아 있는 리워드양
    uint256 private REWARD_RATE; //연간이율

    IERC20 private rewardToken; //리워드용 토큰
    IERC20 private stakeToken; //스테이킹용 토큰

    address private TEAM_POOL; //팀 어드레스

    mapping (address => uint256) private USER_STAKED_AMOUNT; //사용자별 스테이킹 갯수
    mapping (address => uint256) private USER_REWARD; //사용자별 리워드양
    mapping (address => bool) private IS_REGISTED;
    address[] private CONTRACT_LIST;
    mapping (address => uint256) private UPDATED_TIMESTAMP;

    event Stake(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    mapping (address => uint256) private USER_STAKE_TIME; //사용자에 이자확인을 위한 값

    constructor (
        uint256 _rewardRate, //연 이자율
        address _rewardToken, //리워드되는 토큰
        address _stakeToken, //스테이킹하는 토큰
        address _teamPool
    ) internal {
        rewardToken = IERC20(_rewardToken);
        stakeToken = IERC20(_stakeToken);
        REWARD_RATE = _rewardRate;
        TEAM_POOL = _teamPool;
        IS_RUNNING_POOL = false;
    }
    
      //스테이킹
    function stake (address account, uint256 amount) external returns (bool){

        require(IS_RUNNING_POOL == true, "The pool has ended.");
        require(amount > 0, "The pool has ended.");

        _registAddress(account); // 사용자 스테이킹 등록 
        // _updateReward(account); // 리워드 업데이트 , 기존 등록자면 스테이킹에 대한 계산 정리 후 업데이트
        _updateAllReward();

        if(UPDATED_TIMESTAMP[account] <= 0){
            UPDATED_TIMESTAMP[account] = block.timestamp;
            USER_STAKE_TIME[account] = block.timestamp;//유저가 스테이킹한 시간 이용 채굴된 양 확인
        }
 
        //풀 계정으로 토큰 전송처리
        stakeToken.transferFrom(account, address(this), amount); 

        //기존 스테이킹 했던 양이 있다면 해당 계정에 스테이크양 업데이트
        USER_STAKED_AMOUNT[account] = USER_STAKED_AMOUNT[account].add(amount);

        //전체 풀에 STAKE 양을 업데이트
        TOTAL_STAKED_AMOUNT = TOTAL_STAKED_AMOUNT.add(amount);
        
        emit Stake(account, amount);
    }

    //스테이킹 취소
    function Unstake (address account) external returns (bool){

        //리워드양 계산
        // _updateReward(account);
        _updateAllReward();
        //리워드 토큰을 사용자에게 전달
        if(USER_REWARD[account] > 0){
            uint256 rewards = USER_REWARD[account];
            USER_REWARD[account] = 0;
            rewardToken.transfer(account, rewards);
        }
        USER_STAKE_TIME[account] = 0;//유저가 스테이킹한 시간 이용 채굴된 양 확인
        //스테이킹 중인 토큰 사용자에게 전송
        _stake_token_withdraw(account, USER_STAKED_AMOUNT[account]);
    }

    //이자만 출금
    function claimReward (address account) external returns (bool){
        
        // _updateReward(account); //이자 정보 업데이트
        _updateAllReward();

        //없다면 Error
        require(USER_REWARD[account] > 0, "Nothing to claim");

        uint256 withrawAmount = USER_REWARD[account];
        USER_REWARD[account] = 0; //이자금액 초기화

        USER_STAKE_TIME[account] = block.timestamp; //유저가 스테이킹한 시간 이용 채굴된 양 확인

        rewardToken.transfer(account, withrawAmount);
    }

   //전체 스테이킹 양
    function totalStakedAmount() external view returns (uint256){
        return TOTAL_STAKED_AMOUNT;
    }

    //계정당 스테이킹 양 확인
    function stakedAmount(address account) external view returns (uint256){
        return USER_STAKED_AMOUNT[account];
    }

    //계정당 리워드 양 확인
    function rewardAmount(address account) external view returns (uint256){
        return USER_REWARD[account];
    }

    //시작한 리워드 양
    function beginRewardAmount() external view returns (uint256){
         return BEGIN_REWARD;
    }

    //남아 있는 리워드 양
    function remainRewardAmount() external view returns (uint256){
         return REMAIN_REWARD;
    }
	
    //연간 이율 확인
    function ratePool() external view returns (uint256){
        return REWARD_RATE;
    }

    //풀이 동작상태인지 확인
    function IsRunningPool() external view returns (bool){
        return IS_RUNNING_POOL;
    }

    function emergencyTokenExit (address account) external returns (bool){
        uint256 amount = USER_STAKED_AMOUNT[account];
        _stake_token_withdraw(account, amount);

        USER_STAKED_AMOUNT[account] = 0;
        USER_REWARD[account] = 0;

        emit EmergencyWithdraw(account, amount);
    }

   function _initPool() internal {

        //리워드 풀 주소에 입금처리를 한후 실행
        BEGIN_REWARD = rewardToken.balanceOf(address(this));
        //현재 풀에 리워드 갯수 저장
        if(BEGIN_REWARD <= 0){
            return;
        }else{
            REMAIN_REWARD = BEGIN_REWARD;
            //남아있는 리워드 양과 초기 양과 같도록 SET

            _setIsRunningPool(true); //Pool 동작중이라 저장
        }
    }

    //풀의 동작 상태 저장
    function _setIsRunningPool(bool _isRunningPool) internal {
        IS_RUNNING_POOL = _isRunningPool;
    }

    //스테이킹 중인 토큰 전송
    function _stake_token_withdraw (address host, uint256 amount) internal {
        //스테이킹 중인 토큰 전송
        require(USER_STAKED_AMOUNT[host] >= 0);
        //사용자 스테이킹 토큰이 0보다 크거나 같다면

        USER_STAKED_AMOUNT[host] = USER_STAKED_AMOUNT[host].sub(amount);
        //사용자의 양만큼 빼고 

        TOTAL_STAKED_AMOUNT = TOTAL_STAKED_AMOUNT.sub(amount);
        //전체 양을 줄인다.

        stakeToken.transfer(host, amount);
    }

    //[1] 이자 계산 루틴
    // 리워드 양 업데이트
    function _updateReward (address host) internal {

        uint256 elapsed = _elapsedBlock(UPDATED_TIMESTAMP[host]);
        
        if(elapsed <= 0){
            return;
        }
        
        uint256 stakeAmount = USER_STAKED_AMOUNT[host];
        if(stakeAmount <= 0){
            return;
        }
        UPDATED_TIMESTAMP[host] = block.timestamp;
        uint256 baseEarned = _calculateEarn(elapsed, stakeAmount);

        if(REMAIN_REWARD >= baseEarned){

            USER_REWARD[host] = baseEarned.mul(95).div(100).add(USER_REWARD[host]);
            USER_REWARD[TEAM_POOL] = baseEarned.mul(5).div(100).add(USER_REWARD[TEAM_POOL]);
            REMAIN_REWARD = REMAIN_REWARD.sub(baseEarned);
        }else{
            if(REMAIN_REWARD > 0){
                uint256 remainAll = REMAIN_REWARD;
                REMAIN_REWARD = 0;
                USER_REWARD[host] = remainAll.mul(95).div(100).add(USER_REWARD[host]);
                USER_REWARD[TEAM_POOL] = remainAll.mul(5).div(100).add(USER_REWARD[TEAM_POOL]);
     
            }
            _setIsRunningPool(false);
        }
    }

    //스테이킹 시간 리턴
    function _elapsedBlock (uint256 updated) internal view returns (uint256) {
        uint256 open = updated; //기존 저장시간
        uint256 close = block.timestamp; //현재
        return open >= close ? 0 : close - open;   
    }

    //사용자 주소등록
    function _registAddress (address host) internal {
        if(IS_REGISTED[host]){return;}

        IS_REGISTED[host] = true;
        CONTRACT_LIST.push(host);
    }

    //풀종료
    function _endPool(address owner) internal {
        _updateAllReward();

        //First User Stake & Reward withdraw
        for(uint256 i=0; i<CONTRACT_LIST.length; i++){
            address account = CONTRACT_LIST[i];
            //리워드 토큰을 사용자에게 전달
            if(USER_REWARD[account] > 0){
                uint256 rewards = USER_REWARD[account];
                USER_REWARD[account] = 0;
                rewardToken.transfer(account, rewards);
            }
            //스테이킹 중인 토큰 사용자에게 전송
            _stake_token_withdraw(account, USER_STAKED_AMOUNT[account]);
        }   

        //Second Team Reward withdraw
        if(TEAM_POOL != address(0)){
            if(USER_REWARD[TEAM_POOL] > 0){
                uint256 rewards = USER_REWARD[TEAM_POOL];
                USER_REWARD[TEAM_POOL] = 0;
                rewardToken.transfer(TEAM_POOL, rewards);
            }
        }

        //Third Owner saved reward withdraw
        uint256 endRewardAmount = rewardToken.balanceOf(address(this));
        if(endRewardAmount > 0){
            rewardToken.transfer(owner, endRewardAmount);
        }

        //Third End
        _setIsRunningPool(false);
    }

    function _updatePool() internal {
        _updateAllReward();
    }


    function rewordForSecond(address account) public view returns (uint256){
        uint256 stakeAmount = USER_STAKED_AMOUNT[account];
        if(stakeAmount <= 0){
            return 0;
        }

        uint256 oneYearReward = stakeAmount.mul(REWARD_RATE).div(100);
        uint256 oneDayReward = oneYearReward.div(365);
        uint256 oneTimesReward = oneDayReward.div(24);
        uint256 oneMinReward = oneTimesReward.div(60);
        uint256 oneSeconReward = oneMinReward.div(60);
        return oneSeconReward;        
    }

    function userReward(address account) public view returns (uint256){
       return USER_REWARD[account];
    }
    
    function teamPoolAddress() public view returns (address){
       return TEAM_POOL;
    }

    //업데이트 전체 리워드
    function _updateAllReward () internal {
        for(uint256 i=0; i<CONTRACT_LIST.length; i++){
            if(IS_RUNNING_POOL){
                _updateReward(CONTRACT_LIST[i]);
            }
        }
    }

    //현재 까지 스테이킹 양 리턴 
    function _calculateEarn (uint256 elapsed, uint256 staked) internal view returns (uint256) {
        if(staked == 0){return 0;}
        
        if(elapsed <= 0){return 0;}

        uint256 oneYearReward = staked.mul(REWARD_RATE).div(100);
        uint256 oneDayReward = oneYearReward.div(365);
        uint256 oneTimesReward = oneDayReward.div(24);
        uint256 oneMinReward = oneTimesReward.div(60);
        uint256 oneSeconReward = oneMinReward.div(60);
        uint256 secondReward = oneSeconReward.mul(elapsed); // 현재 초당이자
     
        return secondReward;
    }

    function _changeRewardRate (uint256 _rate) internal {
        _updateAllReward();
        REWARD_RATE = _rate;
    }

    function contractListCount () external view returns (uint256) {
        return CONTRACT_LIST.length;
    }
    
    //사용자가 스테이킹한 시간을 확인하기 위한 함수
    function userStakeTime (address account) external view returns (uint256) {
        return USER_STAKE_TIME[account];
    }
    
}

contract DreamStakePool is Ownable, TokenRewardPool{
    
    // string private constant _name = "PoolName";
    // uint256 private constant _rate = 20; //%
    // address private constant _rewardToken = ""; //리워드 풀주소
    // address private constant _stakeToken = ""; //스테이킹하는 토큰
    // address private constant _teamPool = ""; //팀 풀 주소
    // constructor () TokenRewardPool(_rate, _rewardToken, _stakeToken, _teamPool) onlyOwner public{
    //     //extend to do
    // }

////////////// TesetNet /////////////////
    string private name = "PoolName";
       
    constructor (   
        string memory _name,//Pool Name
        uint256 _rate, //연 이자율
        address _rewardToken, //리워드되는 토큰
        address _stakeToken, //스테이킹하는 토큰
        address _teamPool) TokenRewardPool(_rate, _rewardToken, _stakeToken, _teamPool) onlyOwner public{
        name = _name;
    }

    //[1] init : 초기 풀 세팅용
    function initTotalReward () public onlyOwner {
        _initPool();
    }

    function endPool() public onlyOwner {
          _endPool(owner());
    }

    function changeRewardRate (uint256 rate) public onlyOwner {
       _changeRewardRate(rate);
    }

    function updatePool () public onlyOwner {
       _updatePool();
    }  
}