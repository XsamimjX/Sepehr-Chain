package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const canaryInitCode = "602a600055600b6011600039600b6000f360005460005260206000f3"

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: deploy-canary <rpc-url> <private-key>")
		os.Exit(64)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	client, err := ethclient.DialContext(ctx, os.Args[1])
	must(err)
	defer client.Close()

	privateKey, err := crypto.HexToECDSA(os.Args[2])
	must(err)
	from := crypto.PubkeyToAddress(privateKey.PublicKey)
	nonce, err := client.PendingNonceAt(ctx, from)
	must(err)
	gasPrice, err := client.SuggestGasPrice(ctx)
	must(err)
	chainID, err := client.ChainID(ctx)
	must(err)

	transaction := types.NewContractCreation(
		nonce,
		big.NewInt(0),
		250_000,
		gasPrice,
		common.FromHex(canaryInitCode),
	)
	signed, err := types.SignTx(transaction, types.LatestSignerForChainID(chainID), privateKey)
	must(err)
	must(client.SendTransaction(ctx, signed))

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		receipt, receiptErr := client.TransactionReceipt(ctx, signed.Hash())
		if receiptErr == nil {
			must(json.NewEncoder(os.Stdout).Encode(map[string]any{
				"address":         receipt.ContractAddress.Hex(),
				"deployer":        from.Hex(),
				"transactionHash": signed.Hash().Hex(),
			}))
			return
		}
		select {
		case <-ctx.Done():
			must(ctx.Err())
		case <-ticker.C:
		}
	}
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
