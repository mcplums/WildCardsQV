pragma solidity >=0.4.25 <0.6.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/access/roles/MinterRole.sol";

interface LoyaltyToken 
{
    function approve(address _spender, uint256 _amount) external returns (bool);
    function balanceOf(address _ownesr) external view returns (uint256);
    function faucet(uint256 _amount) external;
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
}

interface WildCardToken
{
    function balanceOf(address owner) external view returns (uint256) ;
}

/**
 * @title WildCardsQV
 * @dev the manager for Charitys / votes
 */
contract WildCardsQV is Ownable, MinterRole {
    using SafeMath for uint256;

    uint256 private _totalSupply;
    string public symbol;
    string public name;
    mapping(address => uint256) private _balances;

    //stuff I added
    LoyaltyToken public loyaltyToken;
    WildCardToken public wildCardToken;
    uint256 oneToken = 10**18;
    address burnAddress = 0x000000000000000000000000000000000000dEaD;
    bool voteCreated = false;
    address[] addressesOfCharities;

    event VoteCasted(address voter, uint CharityID, uint256 weight);

    event CharityCreated(
        address creator,
        uint256 CharityID,
        string description,
        uint votingTimeInHours
    );

    enum CharityStatus {IN_PROGRESS, TALLY, ENDED}

    struct Charity {
        address creator;
        CharityStatus status;
        uint256 yesVotes;
        uint256 noVotes;
        string description;
        address[] voters;
        address addressOfCharity; // <--added
        uint expirationTime;
        mapping(address => Voter) voterInfo;
    }

    struct Voter {
        bool hasVoted;
        bool vote;
        uint256 weight;
    }

    mapping(uint256 => Charity) public Charitys;
    uint public CharityCount;

    constructor(LoyaltyToken _addressOfLoyalyTokenContract, WildCardToken _addressOfWildCardTokenContract) public {
        loyaltyToken = _addressOfLoyalyTokenContract;
        wildCardToken = _addressOfWildCardTokenContract;
        symbol = "QVV";
        name = "QV Voting";
    }

    // new function to create a much of Charities at once for voting
    function createVote(address[] memory _addressesOfCharities, uint _voteExpirationTime) public {
        require(!voteCreated, "Vote already created");
        addressesOfCharities = _addressesOfCharities;
        for (uint i = 0; i < _addressesOfCharities.length; i++) {
            createCharity("", _voteExpirationTime, _addressesOfCharities[i]);
        }
        voteCreated = true;
    }

    /**
    * @dev Creates a new Charity.
    * @param _description the text of the Charity
    * @param _voteExpirationTime expiration time in minutes
    */
    function createCharity(
        string memory _description,
        uint _voteExpirationTime,
        address _addressOfCharity
    ) internal onlyOwner returns (uint) {
        require(_voteExpirationTime > 0, "The voting period cannot be 0");
        CharityCount++;

        Charity storage curCharity = Charitys[CharityCount];
        curCharity.creator = msg.sender;
        curCharity.status = CharityStatus.IN_PROGRESS;
        curCharity.expirationTime = now + 60 * _voteExpirationTime * 1 seconds;
        curCharity.description = _description;
        curCharity.addressOfCharity = _addressOfCharity; // <-- new

        emit CharityCreated(
            msg.sender,
            CharityCount,
            _description,
            _voteExpirationTime
        );
        return CharityCount;
    }

    /**
    * @dev sets a Charity to TALLY.
    * @param _CharityID the Charity id
    */
    function setCharityToTally(uint _CharityID)
        external
        validCharity(_CharityID)
        onlyOwner
    {
        require(
            Charitys[_CharityID].status == CharityStatus.IN_PROGRESS,
            "Vote is not in progress"
        );
        require(
            now >= getCharityExpirationTime(_CharityID),
            "voting period has not expired"
        );
        Charitys[_CharityID].status = CharityStatus.TALLY;
    }

    /**
    * @dev sets a Charity to ENDED.
    * @param _CharityID the Charity id
    */
    function setCharityToEnded(uint _CharityID)
        external
        validCharity(_CharityID)
        onlyOwner
    {
        require(
            Charitys[_CharityID].status == CharityStatus.TALLY,
            "Charity should be in tally"
        );
        require(
            now >= getCharityExpirationTime(_CharityID),
            "voting period has not expired"
        );
        Charitys[_CharityID].status = CharityStatus.ENDED;
    }

    /**
    * @dev returns the status of a Charity
    * @param _CharityID the Charity id
    */
    function getCharityStatus(uint _CharityID)
        public
        view
        validCharity(_CharityID)
        returns (CharityStatus)
    {
        return Charitys[_CharityID].status;
    }

    /**
    * @dev returns a Charity expiration time
    * @param _CharityID the Charity id
    */
    function getCharityExpirationTime(uint _CharityID)
        public
        view
        validCharity(_CharityID)
        returns (uint)
    {
        return Charitys[_CharityID].expirationTime;
    }

    function getWinner() public view returns (uint) {
        uint _winner;
        uint _highestVotes;
        for (uint i = 0; i < addressesOfCharities.length; i++) {
            uint _votes = countVotesPerCharity(i);
            if (_votes > _highestVotes) {
                _winner = i;
                _highestVotes = _votes;
            }
        }
        return _winner;
    }

    /**
    * @dev counts the votes for a Charity. Returns (yeays, nays)
    * @param _CharityID the Charity id
    */
    function countVotesPerCharity(uint256 _CharityID) public view returns (uint) {
        uint yesVotes = 0;
        uint noVotes = 0;

        address[] memory voters = Charitys[_CharityID].voters;
        for (uint i = 0; i < voters.length; i++) {
            address voter = voters[i];
            bool vote = Charitys[_CharityID].voterInfo[voter].vote;
            uint256 weight = Charitys[_CharityID].voterInfo[voter].weight;
            if (vote == true) {
                yesVotes += weight;
            } else {
                noVotes += weight;
            }
        }

        return (yesVotes);

    }

    /**
    * @dev casts a vote.
    * @param _CharityID the Charity id
    * @param numTokens number of voice credits
    */
    //changed to remove option of no vote
    function castVote(uint _CharityID, uint numTokens )
        external
        validCharity(_CharityID)
    {
        require(
            getCharityStatus(_CharityID) == CharityStatus.IN_PROGRESS,
            "Charity has expired."
        );
        require(
            !userHasVoted(_CharityID, msg.sender),
            "user already voted on this Charity"
        );
        require(
            getCharityExpirationTime(_CharityID) > now,
            "for this Charity, the voting time expired"
        );

        bool _vote = true; // no negative votes
        _balances[msg.sender] = _balances[msg.sender].sub(numTokens);

        uint256 weight = sqrt(numTokens); // QV Vote

        Charity storage curCharity = Charitys[_CharityID];

        curCharity.voterInfo[msg.sender] = Voter({
            hasVoted: true,
            vote: _vote,
            weight: weight
        });

        curCharity.voters.push(msg.sender);

        emit VoteCasted(msg.sender, _CharityID, weight);
    }

    /**
    * @dev checks if a user has voted
    * @param _CharityID the Charity id
    * @param _user the address of a voter
    */
    function userHasVoted(uint _CharityID, address _user)
        internal
        view
        validCharity(_CharityID)
        returns (bool)
    {
        return (Charitys[_CharityID].voterInfo[_user].hasVoted);
    }

    /**
    * @dev checks if a Charity id is valid
    * @param _CharityID the Charity id
    */
    modifier validCharity(uint _CharityID) {
        require(
            _CharityID > 0 && _CharityID <= CharityCount,
            "Not a valid Charity Id"
        );
        _;
    }

    /**
    * @dev returns the square root (in int) of a number
    * @param x the number (int)
    */
    function sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
    * @dev minting more tokens for an account
    */
    //remove only owner so anyone with ERC721s can mint themselves vote as long as they have the ERC721
    function mint(uint256 amount) public  {
        require(amount >= oneToken, " Minium vote one token");
        // check they have ERC721
        require(wildCardToken.balanceOf(msg.sender)>0, "Does not own a WildCard");
        //burn their loyalty tokens:
        require(loyaltyToken.transferFrom(msg.sender,burnAddress,amount),"Loyalty Token transfer failed");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
    }

    /**
    * @dev returns the balance of an account
    */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

}
