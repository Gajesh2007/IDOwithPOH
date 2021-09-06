import './@openzeppelin/contracts/access/Ownable.sol';
import './@openzeppelin/contracts/utils/math/SafeMath.sol';
import './@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './POH.sol';

pragma solidity ^0.8.0;

contract IDO is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;

    IProofOfHumanity public immutable proofOfHumanity = IProofOfHumanity(0xC5E9dDebb09Cd64DfaCab4011A0D5cEDaf7c9BDb);

    uint256 public immutable softCap;
    uint256 public immutable hardCap;
    uint256 public immutable tokensPerEther;
    uint256 public immutable minContribution;
    uint256 public immutable maxContribution;

    uint256 public immutable startTime;
    uint256 public immutable endTime;

    uint256 public weiRaised;

    bool public finalized;

    mapping(address => uint256) public contributions;
    mapping(address => uint256) public refunds;
    mapping(address => uint256) public claimedTokens;

    event TokenPurchase(address indexed beneficiary, uint256 weiAmount);
    event TokenClaim(address indexed beneficiary, uint256 tokenAmount);
    event Refund(address indexed beneficiary, uint256 weiAmount);
    event IDOFinalized(uint256 weiAmount);

    constructor(
        IERC20 _token,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _tokensPerEther,
        uint256 _minContribution,
        uint256 _maxContribution,
        uint256 _startTime,
        uint256 _endTime
    ) public {
        token = _token;
        softCap = _softCap;
        hardCap = _hardCap;
        tokensPerEther = _tokensPerEther;
        minContribution = _minContribution;
        maxContribution = _maxContribution;
        startTime = _startTime;
        endTime = _endTime;
    }

    receive() external payable {
        require(proofOfHumanity.isRegistered(msg.sender), "The participant is not registered in Proof Of Humanity.");
        _buyTokens(msg.sender);
    }

    function _buyTokens(address beneficiary) internal {
        uint256 weiToHardcap = hardCap.sub(weiRaised);
        uint256 weiAmount = weiToHardcap < msg.value ? weiToHardcap : msg.value;

        _buyTokens(beneficiary, weiAmount);

        uint256 refund = msg.value.sub(weiAmount);
        if (refund > 0) {
            payable(beneficiary).transfer(refund);
        }
    }

    function _buyTokens(address beneficiary, uint256 weiAmount) internal {
        _validatePurchase(beneficiary, weiAmount);

        weiRaised = weiRaised.add(weiAmount);
        contributions[beneficiary] = contributions[beneficiary].add(weiAmount);

        emit TokenPurchase(beneficiary, weiAmount);
    }

    function _validatePurchase(address beneficiary, uint256 weiAmount)
        internal
        view
    {
        require(isOpen(), "IDO: sale is not open");
        require(!hasEnded(), "IDO: sale is over");
        require(
            weiAmount >= minContribution,
            "IDO: min contribution criteria not met"
        );
        require(
            contributions[beneficiary].add(weiAmount) <= maxContribution,
            "IDO: min contribution criteria not met"
        );
        this;
    }

    function claimTokens() external {
        require(hasEnded(), "IDO: IDO is not over");
        require(softCapReached(), "IDO: soft cap not reached, refund is available");
        require(
            contributions[msg.sender] > 0,
            "IDO: nothing to claim"
        );
        uint256 tokens = _getTokenAmount(contributions[msg.sender]);
        contributions[msg.sender] = 0;
        claimedTokens[msg.sender] = tokens;
        token.safeTransfer(msg.sender, tokens);
        emit TokenClaim(msg.sender, tokens);
    }

    function claimRefund() external {
        require(hasEnded(), "IDO: IDO is not over");
        require(!softCapReached(), "IDO: soft cap not reached");
        require(
            contributions[msg.sender] > 0,
            "IDO: nothing to claim"
        );
        uint256 refundAmount = contributions[msg.sender];
        contributions[msg.sender] = 0;
        refunds[msg.sender] = refundAmount;
        payable(msg.sender).transfer(refundAmount);
        emit Refund(msg.sender, refundAmount);
    }

    function endIDO() external onlyOwner {
        require(!finalized, "IDO: IDO is already over");
        finalized = true;
        if (weiRaised > softCap) {
            uint256 totalWeiRaised = address(this).balance;
            payable(owner()).transfer(totalWeiRaised);
        }
        if (weiRaised < hardCap) {
            uint256 unsoldTokens = _getTokenAmount(hardCap.sub(weiRaised));
            token.transfer(owner(), unsoldTokens);
        }
        emit IDOFinalized(weiRaised);
    }

    function withdrawTokens() public onlyOwner {
        require(finalized, "IDO: IDO is not over");
        // uint256 unsoldTokens = _getTokenAmount(hardCap.sub(weiRaised));
        uint256 tokens = token.balanceOf(address(this));
        token.transfer(owner(), tokens);
    }

    function _getTokenAmount(uint256 weiAmount)
        internal
        view
        returns (uint256)
    {
        return weiAmount.mul(tokensPerEther).div(1e18);
    }

    function isOpen() public view returns (bool) {
        return block.timestamp >= startTime && block.timestamp <= endTime;
    }

    function hasEnded() public view returns (bool) {
        return finalized || block.timestamp >= endTime || weiRaised >= hardCap;
    }

    function softCapReached() public view returns (bool) {
        return weiRaised >= softCap;
    }    
}