import React, { useState } from "react";

const BuySell = (props) => {
  const [currentState, setCurrentState] = useState({ action: "buy", step: 1 });
  
  const [quantity, setQuantity] = useState(null);
  
  const updateQuantity = (e) => {
    if (e.target.value === '') 
		{ setQuantity(''); } 
	
	else 
		{ setQuantity(Number(e.target.value)); }
  };
  
  const estimatedCost = (quantity || 0) * props.marketPrice;
  
  const hasInsufficientFunds = estimatedCost > props.userBalance;
  
  const hasInsufficientQuantity = quantity > props.userHoldings
  
  const isQuantityInvalid = () => {
    if (quantity === '' || quantity <= 0 || !Number.isInteger(quantity)) {
      return true;
    } else {
      return false;
    }
  };
  
  const quantityInvalid = isQuantityInvalid();

  const nextStep = () =>
    setCurrentState({ ...currentState, step: currentState.step + 1 });
  const prevStep = () =>
    setCurrentState({ ...currentState, step: currentState.step - 1 });
  const buyState = () => setCurrentState({ action: "buy", step: 1 });
  const sellState = () => setCurrentState({ action: "sell", step: 1 });


  return (
    <>
      {currentState.action === "buy" && currentState.step === 1 && (
        <div className={hasInsufficientFunds ? 'bs-parent-insufficient' : 'bs-parent-container'}>
		  
          <div className='bs-button-container'>
            <button onClick={buyState} 
			className={currentState.action === 'buy' ? 'buy-sell-button-active' : 'buy-sell-button'}>Buy</button>
            <button onClick={sellState} 
			className={currentState.action === 'sell' ? 'buy-sell-button-active' : 'buy-sell-button'}>Sell</button>
          </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Buy</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-shares-wrapper'>
          	<label>Shares</label>
		  	</div>
          	<form>
            	<input type="number" placeholder="0" name="quantity" min ='0' step="1" className='shares-input' 
          		value={quantity} onChange={updateQuantity}/>
          	</form>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Estimated Cost</p>
		  	</div>
		  	<div>
		  	<p> ${estimatedCost.toFixed(2)} </p>
		  	</div>
		  </div>
		  
		  <div>
          <button className='next' onClick={nextStep} disabled={hasInsufficientFunds || quantityInvalid}>Next</button>
		  </div>
		  
		  <hr />		  
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Available Cash</p>
		  	</div>
		  	<div>
		  	<p> {props.userBalance} </p>
		  	</div>
		  </div>
		  
		  {hasInsufficientFunds && (
			  <p>Insufficient funds for this purchase</p>
		  )}
		  
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 1 && (
        <div className={hasInsufficientQuantity ? 'bs-parent-insufficient' : 'bs-parent-container'}>
		  
          <div className='bs-button-container'>
          <button onClick={buyState} 
		className={currentState.action === 'buy' ? 'buy-sell-button-active' : 'buy-sell-button'}>Buy</button>
          <button onClick={sellState} 
		className={currentState.action === 'sell' ? 'buy-sell-button-active' : 'buy-sell-button'}>Sell</button>
          </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Sell</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-shares-wrapper'>
          	<label>Shares</label>
		  	</div>
          	<form>
            	<input type="number" placeholder="0" name="quantity" min ='0' step="1" className='shares-input' 
          		value={quantity} onChange={updateQuantity}/>
          	</form>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Estimated Value</p>
		  	</div>
		  	<div>
		  	<p> ${estimatedCost.toFixed(2)} </p>
		  	</div>
		  </div>
		  
		  <div>
          <button className='next' onClick={nextStep} disabled={hasInsufficientQuantity || quantityInvalid}>Next</button>
		  </div>
		  
		  <hr />		  
		 
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Available Shares</p>
		  	</div>
		  	<div>
		  	<p>{props.userHoldings}</p>
		  	</div>
		  </div>
		  
		  {hasInsufficientQuantity && (
			  <p>Insufficient shares for this sale</p>
		  )}
		  
        </div>
      )}

      {currentState.action === "buy" && currentState.step === 2 && (
        <div className='bs-parent-container-two'>
		  
		  <div>
          <button onClick={prevStep} className='bs-back-button'> &lt; back</button>
		  </div>
		  		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Buy</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Quantity</p>
		  	</div>
		  	<div>
		  	<p>{quantity}</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Cost</p>
		  	</div>
		  	<div>
		  	<p>${estimatedCost.toFixed(2)}</p>
		  	</div>
		  </div>
		  
		  <div>
		  <form method='POST' action='/position'>
	   	 	<input type="hidden" name="authenticity_token" 
			value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
	    	<input type="hidden" name="symbol" value={props.symbol}/>
		  	<input type='submit' name='commit' value='buy' className='next'/>
			<input type='hidden' value={quantity} name='quantity'/>
		  </form>
		  </div>
		  
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 2 && (
        <div className='bs-parent-container-two'>
		  
		  <div>
          <button onClick={prevStep} className='bs-back-button'> &lt; back</button>
		  </div>
		  		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Sell</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Quantity</p>
		  	</div>
		  	<div>
		  	<p>{quantity}</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Value</p>
		  	</div>
		  	<div>
		  	<p>${estimatedCost.toFixed(2)}</p>
		  	</div>
		  </div>
		  
		  <div>
		  <form method='POST' action='/position'>
	   	 	<input type="hidden" name="authenticity_token" 
			value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
	    	<input type="hidden" name="symbol" value={props.symbol}/>
		  	<input type='submit' name='commit' value='sell' className='next'/>
			<input type='hidden' value={quantity} name='quantity'/>
		  </form>
		  </div>
		  
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 3 && (
        <div className='bs-parent-container-two'>
		  
		  <div className='bs-containers'>
          <h2>Order Submitted!</h2>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p> Submitted</p>
		  	</div>
		  	<div>
		  	<p>{new Date().toLocaleTimeString()}</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p> Order Type</p>
		  	</div>
		  	<div>
		  	<p> Market Sell</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Shares</p>
		  	</div>
		  	<div>
		  	<p>{quantity}</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Value</p>
		  	</div>
		  	<div>
		  	<p>${estimatedCost.toFixed(2)}</p>
		  	</div>
		  </div>
		  
          <button onClick={buyState} className='next'>Done</button>
        </div>
      )}

      {currentState.action === "buy" && currentState.step === 3 && (
        <div className='bs-parent-container-two'>
		  
		  <div className='bs-containers'>
          <h2>Order Submitted!</h2>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p> Submitted</p>
		  	</div>
		  	<div>
		  	<p>{new Date().toLocaleTimeString()}</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p> Order Type</p>
		  	</div>
		  	<div>
		  	<p> Market Buy</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Shares</p>
		  	</div>
		  	<div>
		  	<p>{quantity}</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Cost</p>
		  	</div>
		  	<div>
		  	<p>${estimatedCost.toFixed(2)}</p>
		  	</div>
		  </div>
		  
          <button onClick={buyState} className='next'>Done</button>
        </div>
      )}
    </>
  );
};

export default BuySell;
