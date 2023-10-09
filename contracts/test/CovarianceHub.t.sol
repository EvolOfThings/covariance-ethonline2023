// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Safe, Enum } from 'safe-contracts/Safe.sol';
import { SafeProxyFactory } from 'safe-contracts/proxies/SafeProxyFactory.sol';
import { Test, console2 } from 'forge-std/Test.sol';
import { Vm } from 'forge-std/Vm.sol';
import '../src/CovarianceHub.sol';
import '../src/external/IERC20.sol';

contract CovarianceHubTest is Test {
    IERC20 private constant WETH = IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    SafeProxyFactory safeFactory = SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);
    Safe safeSingleton = Safe(payable(0x29fcB43b46531BcA003ddC8FCB67FFE91900C762));
    CovarianceHub public testContract;
    Safe public safeAccount;

    Vm.Wallet company = vm.createWallet('company');
    Vm.Wallet contributor = vm.createWallet('contributor');

    struct TxDetails {
        Vm.Wallet account;
        address to;
        uint256 value;
        bytes data;
        Enum.Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address payable refundReceiver;
    }

    function setUp() public {
        vm.createSelectFork('goerli');
        testContract = new CovarianceHub();

        address[] memory owners = new address[](1);
        owners[0] = company.addr;

        bytes memory setupTx = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            1,
            address(0),
            '',
            address(0),
            0,
            0,
            address(0)
        );

        safeAccount = Safe(payable(address(safeFactory.createProxyWithNonce({
            _singleton: address(safeSingleton),
            initializer: setupTx,
            saltNonce: 0
        }))));

        // deployCodeTo('Safe.sol', address(safeAccount));
    }

    function getDataHash (TxDetails memory details) private returns (bytes32) {
        bytes32 txHash = safeAccount.getTransactionHash({
            to: details.to,
            value: details.value,
            data: details.data,
            operation: details.operation,
            safeTxGas: details.safeTxGas,
            baseGas: details.baseGas,
            gasPrice: details.gasPrice,
            gasToken: details.gasToken,
            refundReceiver: details.refundReceiver,
            _nonce: safeAccount.nonce()
        });

        return keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            txHash
        ));
    }

    function execSafeTx (TxDetails memory details) private returns (bool) {
        bytes32 dataHash = getDataHash(details);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            details.account,
            dataHash
        );

        try safeAccount.execTransaction({
            to: details.to,
            value: details.value,
            data: details.data,
            operation: details.operation,
            safeTxGas: details.safeTxGas,
            baseGas: details.baseGas,
            gasPrice: details.gasPrice,
            gasToken: details.gasToken,
            refundReceiver: details.refundReceiver,
            signatures: abi.encodePacked(r, s, v + 4)
        }) returns (bool success) {
            return success;
        }
        catch {
            return false;
        }
    }

    function createCampaignViaSafe () public returns (bool) {
        return createCampaignViaSafe(IERC20(address(0)), 0);
    }

    function createCampaignViaSafe (
        IERC20 rewardToken,
        uint rewardAmount
    ) public returns (bool) {
        Challenge[] memory challenges = new Challenge[](2);
        challenges[0] = Challenge({
            kpi: 'Bring customers',
            points: 10,
            maxContributions: 3,
            contributionsSpent: 0
        });
        challenges[1] = Challenge({
            kpi: 'Increase hackathon participation',
            points: 20,
            maxContributions: 5,
            contributionsSpent: 0
        });

        bytes memory data = abi.encodeWithSelector(
            CovarianceHub.createCampaign.selector,
            Campaign({
                initiator: safeAccount,
                title: 'Test Campaign',
                ipfsCid: '',
                rewardToken: rewardToken,
                rewardAmount: rewardAmount,
                challenges: challenges
            })
        );

        return execSafeTx(TxDetails({
            account: company,
            to: address(testContract),
            value: 0,
            data: data,
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(0)
        }));
    }

    function test_campaignContributions() public {
        createCampaignViaSafe();
        vm.prank(contributor.addr);
        Contribution[] memory contributions = new Contribution[](2);
        contributions[0] = Contribution({
            campaignId: 1,
            challengeIndex: 0,
            amount: 1
        });
        contributions[1] = Contribution({
            campaignId: 1,
            challengeIndex: 1,
            amount: 2
        });
        testContract.contribute(contributions);

        Contribution[] memory contribs = testContract.campaignContributions(1);
        assertEq(contribs[0].campaignId, 1);
        assertEq(contribs[0].challengeIndex, 0);
        assertEq(contribs[0].amount, 1);
        assertEq(contribs[1].campaignId, 1);
        assertEq(contribs[1].challengeIndex, 1);
        assertEq(contribs[1].amount, 2);
    }

    function test_contribute_shouldStoreContributions() public {
        createCampaignViaSafe();
        vm.prank(contributor.addr);
        Contribution[] memory contributions = new Contribution[](2);
        contributions[0] = Contribution({
            campaignId: 1,
            challengeIndex: 0,
            amount: 1
        });
        contributions[1] = Contribution({
            campaignId: 1,
            challengeIndex: 1,
            amount: 2
        });
        testContract.contribute(contributions);

        Contribution memory contrib1 = testContract.contribution(1);
        Contribution memory contrib2 = testContract.contribution(2);
        assertEq(contrib1.campaignId, 1);
        assertEq(contrib1.challengeIndex, 0);
        assertEq(contrib1.amount, 1);
        assertEq(contrib2.campaignId, 1);
        assertEq(contrib2.challengeIndex, 1);
        assertEq(contrib2.amount, 2);
    }

    function test_contributeZeroAmount_shouldRevert() public {
        createCampaignViaSafe();
        vm.prank(contributor.addr);
        Contribution[] memory contributions = new Contribution[](1);
        contributions[0] = Contribution({
            campaignId: 1,
            challengeIndex: 0,
            amount: 0
        });
        vm.expectRevert(abi.encodeWithSelector(
            InvalidContribution.selector,
            'amount'
        ));
        testContract.contribute(contributions);
    }

    function test_contribute() public {
        createCampaignViaSafe();
        vm.prank(contributor.addr);
        Contribution[] memory contributions = new Contribution[](1);
        contributions[0] = Contribution({
            campaignId: 1,
            challengeIndex: 0,
            amount: 1
        });
        testContract.contribute(contributions);
    }

    function test_contributeNonExistingCampaign_shouldRevert() public {
        createCampaignViaSafe();
        vm.prank(contributor.addr);
        Contribution[] memory contributions = new Contribution[](1);
        contributions[0] = Contribution({
            campaignId: 123,
            challengeIndex: 0,
            amount: 1
        });
        vm.expectRevert(abi.encodeWithSelector(
            InvalidContribution.selector,
            'campaignId'
        ));
        testContract.contribute(contributions);
    }

    function test_contributeNonExistingChallenge_shouldRevert() public {
        createCampaignViaSafe();
        vm.prank(contributor.addr);
        Contribution[] memory contributions = new Contribution[](1);
        contributions[0] = Contribution({
            campaignId: 1,
            challengeIndex: 123,
            amount: 1
        });
        vm.expectRevert(abi.encodeWithSelector(
            InvalidContribution.selector,
            'challengeIndex'
        ));
        testContract.contribute(contributions);
    }

    function test_campaignWithRewardHasBalance_txSucceeds() public {
        deal(address(WETH), address(safeAccount), 1 ether);
        bool success = createCampaignViaSafe(WETH, 1 ether);
        assertTrue(success);
    }

    function test_campaignWithRewardNoBalance_txShouldFail() public {
        bool success = createCampaignViaSafe(WETH, 1 ether);
        assertFalse(success);
    }

    function test_createCampaignTwice_getAccountCampaigns() public {
        createCampaignViaSafe();
        createCampaignViaSafe();
        uint[] memory expected = new uint[](2);
        expected[0] = 1;
        expected[1] = 2;
        uint[] memory campaigns = testContract.campaignsByAccount(safeAccount);
        assertEq(campaigns, expected);
    }

    function test_createCampaignViaSafe_getAccountCampaigns() public {
        vm.startPrank(company.addr);
        createCampaignViaSafe();
        uint[] memory expected = new uint[](1);
        expected[0] = 1;
        uint[] memory campaigns = testContract.campaignsByAccount(safeAccount);
        assertEq(campaigns, expected);
    }

    function test_createCampaignNotAsSender_shouldRevert() public {
        vm.startPrank(company.addr);
        vm.expectRevert(SenderIsNotInitiator.selector);
        testContract.createCampaign(Campaign({
            initiator: safeAccount,
            title: 'Test Campaign',
            ipfsCid: '',
            rewardToken: IERC20(address(0)),
            rewardAmount: 0,
            challenges: new Challenge[](1)
        }));
    }
}