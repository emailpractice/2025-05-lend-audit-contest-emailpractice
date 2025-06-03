    function supply(uint256 _amount, address _token) external {
        address _lToken = lendStorage.underlyingTolToken(_token); //@seashell address _token is not all allowed,
        //@seashell only protocol supported tokens are allowed.(has coressponding lToken)  
        //

        require(_lToken != address(0), "Unsupported Token"); 
//@seashell if mapping hasn't registered  _token, it will return address(0)   
//@seashell Check if the token is supported by the protocol. So below use _token instead of _lToken is maybe fine


        require(_amount > 0, "Zero supply amount");

        // Transfer tokens from the user to the contract
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

//@seashell 給1token 合約approve 真代幣的數量。 未來要把錢轉給1token合約
        _approveToken(_token, _lToken, _amount);

        // Get exchange rate before mint
        uint256 exchangeRateBefore = LTokenInterface(_lToken).exchangeRateStored(); //在src/Ltoken.sol裡面
        //@seashell       If there are no tokens minted: exchangeRate = initialExchangeRate
        //@seashell Otherwise: exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
    

        // Mint lTokens
        require(LErc20Interface(_lToken).mint(_amount) == 0, "Mint failed"); //@seashell在src/LErc20.sol
        // @audit: mint是external 然後沒有modifier的。會呼叫Ltoken的mintInternal  (internal nonReentrant)
// mintInternal會呼叫同合約的accure interest()，然後再呼叫mintFresh()。

        // Calculate actual minted tokens using exchangeRate from before mint
                //@audit: rounding error might happen in edge case. need to know more about exchagerateBefore
        uint256 mintTokens = (_amount * 1e18) / exchangeRateBefore;

//@seashell這個合約要是only authorized才能呼叫成功addSupply。 他就是在一個mapping 裡面紀錄一下，"現在還有多一個這種asset的token"
        lendStorage.addUserSuppliedAsset(msg.sender, _lToken);

        lendStorage.distributeSupplierLend(_lToken, msg.sender);

        // Update total investment using calculated mintTokens
        lendStorage.updateTotalInvestment(
            msg.sender, _lToken, lendStorage.totalInvestment(msg.sender, _lToken) + mintTokens
        );

        emit SupplySuccess(msg.sender, _lToken, _amount, mintTokens);
    }


    function _approveToken(address _token, address _approvalAddress, uint256 _amount) internal {
        //@seashell this contract's allowance for 1token.
        uint256 currentAllowance = IERC20(_token).allowance(address(this), _approvalAddress);

//@seashell 檢查此合約對1token的授權金額是否足夠，那代表這個合約未來想轉錢過去給1token (轉給他用戶存進來的真代幣，數量是真代幣的數量)
        if (currentAllowance < _amount) {
            //@seashell 如果當前授權金額大於0，則先將其設置為0
            if (currentAllowance > 0) {
                IERC20(_token).safeApprove(_approvalAddress, 0);
            }
            IERC20(_token).safeApprove(_approvalAddress, _amount);
        }
    }

    function exchangeRateStoredInternal() internal view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return initialExchangeRateMantissa;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint256 totalCash = getCashPrior();
            uint256 cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;
            uint256 exchangeRate = cashPlusBorrowsMinusReserves * expScale / _totalSupply;

            return exchangeRate;
        }
    }

        function mintInternal(uint256 mintAmount) internal nonReentrant {
        accrueInterest();
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        mintFresh(msg.sender, mintAmount);
    }

        function accrueInterest() public virtual override returns (uint256) {
        /* Remember the initial block number */
        uint256 currentBlockNumber = getBlockNumber(); //@seashell用block.number取得現在區塊記錄到哪。看是哪條鍊就哪條的
        uint256 accrualBlockNumberPrior = accrualBlockNumber; //@seashell Block number that interest was last accrued at


        /* Short-circuit accumulating 0 interest */
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return NO_ERROR; //@seashell no_error是常數0。 這樣寫是常見的，用語義化的方式表達正確或錯誤。
            // @audit:原本在想能不能硬湊出回傳值是0來蒙騙，但下面的return都不是return變數，都是return這個常數，所以應該沒問題
        }

        /* Read the previous values out of storage */
        uint256 cashPrior = getCashPrior();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        //@seashell interestRateModel 只是一個抽象合約。 要找繼承interestRateModel的合約們
        //@seashell 初始化的時候選哪個要找繼承interestRateModel，這邊呼叫的就是那個
        //@seashell 但我實在不知道它選誰，所以我就隨便選一個合約看具體實現。 這個repo雖然有更多人是繼承interestRatemodel
        // 但只有兩個是有
        //最後選定了 jumpRateModelV2.sol 因為它至少是V2 看起來像是比較新的實現
        uint256 borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);

        require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
        uint256 interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew =
            mul_ScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
        uint256 borrowIndexNew = mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockNumber = currentBlockNumber;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);

        return NO_ERROR;